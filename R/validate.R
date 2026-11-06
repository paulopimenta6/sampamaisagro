classify_coordinates <- function(latitude, longitude, bbox) {
  missing <- is.na(latitude) & is.na(longitude)
  incomplete <- xor(is.na(latitude), is.na(longitude))
  invalid <- !missing & !incomplete & (latitude < -90 | latitude > 90 | longitude < -180 | longitude > 180)
  outside <- !missing & !incomplete & !invalid &
    (longitude < bbox$xmin | longitude > bbox$xmax | latitude < bbox$ymin | latitude > bbox$ymax)
  status <- rep("valid_source_coordinate", length(latitude))
  status[missing] <- "missing_coordinate"
  status[incomplete] <- "incomplete_coordinate"
  status[invalid] <- "invalid_coordinate"
  status[outside] <- "outside_study_area"
  status
}

#' Validate normalized equipment records
#'
#' @param data Canonical equipment data.
#' @param config Project configuration.
#' @return List containing annotated data, eligible records, quarantine, summary and issues.
#' @export
validate_equipment <- function(data, config = read_sampa_config()) {
  required <- c("equipment_id", "equipment_name", "category", "latitude", "longitude")
  missing_columns <- setdiff(required, names(data))
  if (length(missing_columns)) stop("Colunas obrigatorias ausentes: ", paste(missing_columns, collapse = ", "))
  data$coordinate_status <- classify_coordinates(data$latitude, data$longitude, config$spatial$bbox)
  data$within_municipality <- rep(NA, nrow(data))
  boundary_file <- file.path(config$data_dir, "osm", "sao-paulo-boundary.geojson")
  if (file.exists(boundary_file)) {
    rows <- which(is.finite(data$latitude) & is.finite(data$longitude) &
      abs(data$latitude) <= 90 & abs(data$longitude) <= 180)
    if (length(rows)) {
      points <- sf::st_as_sf(data[rows, ], coords = c("longitude", "latitude"), crs = 4326)
      boundary <- sf::st_read(boundary_file, quiet = TRUE)
      data$within_municipality[rows] <- lengths(sf::st_intersects(points, boundary)) > 0
    }
  }
  data$quality_flags <- ifelse(is.na(data$equipment_name) | !nzchar(trimws(as.character(data$equipment_name))), "missing_name", "")
  data$quality_flags <- ifelse(is.na(data$category) | !nzchar(trimws(as.character(data$category))),
    paste0(data$quality_flags, ifelse(nzchar(data$quality_flags), "|", ""), "missing_category"), data$quality_flags)

  duplicated_ids <- duplicated(data$record_version_id %||% data$equipment_id)
  data$quality_flags[duplicated_ids] <- paste0(data$quality_flags[duplicated_ids],
    ifelse(nzchar(data$quality_flags[duplicated_ids]), "|", ""), "duplicate_record")

  eligible <- data$coordinate_status %in% c("valid_source_coordinate", "derived_geocode") & !duplicated_ids
  quarantine <- data[!eligible, , drop = FALSE]
  issues <- data.frame(
    issue = c("missing_coordinate", "incomplete_coordinate", "invalid_coordinate", "outside_study_area",
      "missing_category", "duplicate_record"),
    n = c(
      sum(data$coordinate_status == "missing_coordinate"),
      sum(data$coordinate_status == "incomplete_coordinate"),
      sum(data$coordinate_status == "invalid_coordinate"),
      sum(data$coordinate_status == "outside_study_area"),
      sum(grepl("missing_category", data$quality_flags, fixed = TRUE)),
      sum(grepl("duplicate_record", data$quality_flags, fixed = TRUE))
    ), stringsAsFactors = FALSE
  )
  summary <- data_quality_summary(data)
  list(data = data, eligible = data[eligible, , drop = FALSE], quarantine = quarantine,
    summary = summary, issues = issues)
}

#' Summarize data completeness by category
#'
#' The denominator is every profile in the supplied consolidated analytical data,
#' before spatial eligibility exclusions. Profiles removed during earlier
#' consolidation are not represented. Each percentage uses its category's `n`.
#' Missing text includes `NA`, empty strings and whitespace-only strings.
#'
#' @param data Annotated equipment data.
#' @return Data frame with deterministic counts and proportions.
#' @export
data_quality_summary <- function(data) {
  missing_text <- function(x) is.na(x) | !nzchar(trimws(as.character(x)))
  missing_category <- missing_text(data$category)
  missing_cep <- if (is.null(data$postal_code)) rep(TRUE, nrow(data)) else missing_text(data$postal_code)
  category <- as.character(data$category)
  category[missing_category] <- "Sem categoria"
  coordinate_ok <- data$coordinate_status %in% c("valid_source_coordinate", "derived_geocode")
  duplicated_ids <- duplicated(data$record_version_id %||% data$equipment_id)
  indicators <- list(
    missing_coordinate = data$coordinate_status %in% "missing_coordinate",
    incomplete_coordinate = data$coordinate_status %in% "incomplete_coordinate",
    invalid_coordinate = data$coordinate_status %in% "invalid_coordinate",
    outside_study_area = data$coordinate_status %in% "outside_study_area",
    spatial_eligible = coordinate_ok & !duplicated_ids,
    missing_name = missing_text(data$equipment_name),
    missing_category = missing_category,
    missing_cep = missing_cep
  )
  split_data <- split(seq_len(nrow(data)), category)
  summary <- data.frame(category = as.character(names(split_data)),
    n = as.integer(lengths(split_data)), stringsAsFactors = FALSE)
  summary$coordinate_n <- vapply(split_data, function(i) sum(coordinate_ok[i]), integer(1))
  summary$coordinate_pct <- 100 * summary$coordinate_n / summary$n
  summary$cep_n <- vapply(split_data, function(i) sum(!missing_cep[i]), integer(1))
  for (name in names(indicators)) {
    count_col <- paste0(name, "_n")
    summary[[count_col]] <- vapply(split_data, function(i) sum(indicators[[name]][i]), integer(1))
    summary[[paste0(name, "_pct")]] <- 100 * summary[[count_col]] / summary$n
  }
  summary[order(-summary$n), , drop = FALSE]
}
