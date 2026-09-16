#' Validate individual or batch origin records
#'
#' @param origins Data frame with `query_id` and either `cep` or coordinates.
#' @param config Project configuration.
#' @return List with valid rows and a row-level error table.
#' @export
validate_origins <- function(origins, config = read_sampa_config()) {
  origins <- as.data.frame(origins, stringsAsFactors = FALSE)
  n <- nrow(origins)
  defaults <- list(query_id = sprintf("q-%06d", seq_len(n)), cep = empty_chr(n),
    latitude = rep(NA_real_, n), longitude = rep(NA_real_, n),
    k = rep(config$proximity$default_k, n), radius_m = rep(config$proximity$default_radius_m, n))
  for (nm in names(defaults)) if (!nm %in% names(origins)) origins[[nm]] <- defaults[[nm]]
  for (nm in c("k", "radius_m")) {
    missing <- is.na(origins[[nm]]) | trimws(as.character(origins[[nm]])) == ""
    origins[[nm]][missing] <- defaults[[nm]][missing]
  }
  origins$query_id <- as.character(origins$query_id)
  raw_cep <- as.character(origins$cep)
  origins$cep <- normalize_cep(origins$cep)
  origins$latitude <- suppressWarnings(as.numeric(origins$latitude))
  origins$longitude <- suppressWarnings(as.numeric(origins$longitude))
  origins$k <- suppressWarnings(as.numeric(origins$k))
  origins$radius_m <- suppressWarnings(as.numeric(origins$radius_m))

  errors <- list()
  add_error <- function(rows, field, code, message) {
    if (!length(rows)) return()
    errors[[length(errors) + 1L]] <<- data.frame(row = rows, query_id = origins$query_id[rows],
      field = field, code = code, message = message, stringsAsFactors = FALSE)
  }
  add_error(which(is.na(origins$query_id) | !nzchar(origins$query_id)), "query_id", "missing", "query_id e obrigatorio")
  add_error(which(duplicated(origins$query_id) | duplicated(origins$query_id, fromLast = TRUE)),
    "query_id", "duplicate", "query_id deve ser unico")
  has_cep <- !is.na(origins$cep)
  has_lat <- !is.na(origins$latitude)
  has_lon <- !is.na(origins$longitude)
  has_pair <- has_lat & has_lon
  add_error(which(!is.na(raw_cep) & nzchar(trimws(raw_cep)) & is.na(origins$cep)),
    "cep", "invalid_cep", "CEP deve conter oito digitos, preservando o zero inicial")
  add_error(which(has_cep & (has_lat | has_lon)), "origin", "multiple_methods", "informe CEP ou coordenadas, nao ambos")
  add_error(which(!has_cep & !has_lat & !has_lon), "origin", "missing", "informe CEP ou latitude e longitude")
  add_error(which(xor(has_lat, has_lon)), "coordinates", "incomplete", "latitude e longitude devem ser informadas juntas")
  add_error(which(has_pair & (origins$latitude < -90 | origins$latitude > 90)), "latitude", "range", "latitude fora de [-90, 90]")
  add_error(which(has_pair & (origins$longitude < -180 | origins$longitude > 180)), "longitude", "range", "longitude fora de [-180, 180]")
  add_error(which(!is.finite(origins$k) | origins$k != trunc(origins$k) | origins$k < 1 | origins$k > 1000), "k", "range", "k deve ser inteiro entre 1 e 1000")
  add_error(which(is.na(origins$radius_m) | origins$radius_m <= 0 | origins$radius_m > 100000),
    "radius_m", "range", "radius_m deve estar entre 0 e 100000")
  errors <- if (length(errors)) dplyr::bind_rows(errors) else data.frame(row = integer(), query_id = character(),
    field = character(), code = character(), message = character(), stringsAsFactors = FALSE)
  bad_rows <- unique(errors$row)
  list(valid = origins[!seq_len(n) %in% bad_rows, , drop = FALSE], errors = errors, annotated = origins)
}

#' Resolve a CEP from the local cache, or explicitly prepare it online
#'
#' @param cep Postal code.
#' @param config Project configuration.
#' @param refresh Ignore a cached result.
#' @return One-row data frame with coordinates and provenance.
#' @export
geocode_cep <- function(cep, config = read_sampa_config(), refresh = FALSE) {
  cep <- normalize_cep(cep)
  if (is.na(cep)) stop("CEP deve conter oito digitos.")
  ensure_project_dirs(config)
  cache_path <- file.path(config$data_dir, "cache", "cep", paste0(cep, ".rds"))
  if (file.exists(cache_path) && !isTRUE(refresh)) {
    cached <- readRDS(cache_path)
    if (identical(attr(cached, "cache_schema"), 2L)) return(cached)
  }
  if (isTRUE(config$geocoding$offline)) {
    stop("CEP ", cep, " ainda n\u00e3o est\u00e1 no \u00edndice local. Com internet, execute: Rscript scripts/prepare_ceps.R ",
      cep, ". Ou informe latitude e longitude (funcionam offline).")
  }
  url <- paste0(sub("/$", "", config$geocoding$endpoint), "/", cep)
  response <- perform_request(url, config)
  httr2::resp_check_status(response)
  body <- httr2::resp_body_json(response, simplifyVector = TRUE)
  latitude <- suppressWarnings(as.numeric(body$lat %||% NA_real_))
  longitude <- suppressWarnings(as.numeric(body$lng %||% NA_real_))
  status <- if (is.finite(latitude) && is.finite(longitude)) "ok" else "no_coordinates"
  if (isTRUE(config$geocoding$require_sao_paulo) &&
      !(tolower(body$city %||% "") == "sao paulo" || tolower(body$city %||% "") == "s\u00e3o paulo")) {
    status <- "outside_sao_paulo"
  }
  result <- data.frame(cep = cep, latitude = latitude, longitude = longitude,
    city = body$city %||% NA_character_, state = body$state %||% NA_character_,
    address = body$address %||% NA_character_,
    geocoder = "AwesomeAPI CEP (ponto aproximado do CEP)", geocoded_at = utc_now(),
    geocode_status = status, origin_quality_flag = "approximate_cep", stringsAsFactors = FALSE)
  attr(result, "raw_response") <- body
  attr(result, "cache_schema") <- 2L
  atomic_write_json(list(url = url, retrieved_at = utc_now(), response = body),
    file.path(config$data_dir, "cache", "cep", paste0(cep, ".json")))
  atomic_save_rds(result, cache_path)
  result
}

#' Resolve validated origins to coordinates
#'
#' @param origins Valid or unvalidated origin data frame.
#' @param config Project configuration.
#' @param refresh_geocodes Ignore CEP cache.
#' @return List with resolved valid origins and row-level errors.
#' @export
resolve_origins <- function(origins, config = read_sampa_config(), refresh_geocodes = FALSE) {
  checked <- validate_origins(origins, config)
  valid <- checked$valid
  if (!nrow(valid)) return(list(valid = valid, errors = checked$errors))
  valid$.source_row <- match(valid$query_id, checked$annotated$query_id)
  valid$origin_method <- ifelse(!is.na(valid$cep), "cep", "coordinates")
  valid$origin_quality_flag <- ifelse(valid$origin_method == "cep", "approximate_cep", "provided_coordinates")
  valid$geocode_source <- ifelse(valid$origin_method == "cep", NA_character_, "provided_by_researcher")
  valid$geocode_precision <- ifelse(valid$origin_method == "cep", NA_character_, "point_as_provided")
  valid$geocoded_at <- NA_character_
  errors <- checked$errors
  cep_values <- unique(valid$cep[valid$origin_method == "cep"])
  delay <- 1 / max(as.numeric(config$geocoding$requests_per_second %||% 2), 0.01)
  for (cep in cep_values) {
    rows <- which(valid$origin_method == "cep" & valid$cep == cep)
    result <- tryCatch(geocode_cep(cep, config, refresh_geocodes), error = identity)
    if (inherits(result, "error") || !identical(result$geocode_status[[1]], "ok")) {
      errors <- dplyr::bind_rows(errors, data.frame(row = valid$.source_row[rows], query_id = valid$query_id[rows], field = "cep",
        code = "geocode_failed", message = if (inherits(result, "error")) conditionMessage(result) else result$geocode_status[[1]],
        stringsAsFactors = FALSE))
      valid$latitude[rows] <- NA_real_
      valid$longitude[rows] <- NA_real_
    } else {
      valid$latitude[rows] <- result$latitude[[1]]
      valid$longitude[rows] <- result$longitude[[1]]
      valid$geocode_source[rows] <- result$geocoder[[1]]
      valid$geocode_precision[rows] <- "postcode_provider_point"
      valid$geocoded_at[rows] <- result$geocoded_at[[1]]
    }
    if (length(cep_values) > 1L && !isTRUE(config$geocoding$offline)) Sys.sleep(delay)
  }
  resolved <- is.finite(valid$latitude) & is.finite(valid$longitude)
  valid$.source_row <- NULL
  list(valid = valid[resolved, , drop = FALSE], errors = errors)
}
