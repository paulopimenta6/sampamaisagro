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
  data$quality_flags <- ifelse(is.na(data$equipment_name) | !nzchar(data$equipment_name), "missing_name", "")
  data$quality_flags <- ifelse(is.na(data$category) | !nzchar(data$category),
    paste0(data$quality_flags, ifelse(nzchar(data$quality_flags), "|", ""), "missing_category"), data$quality_flags)

  duplicated_ids <- duplicated(data$record_version_id %||% data$equipment_id)
  data$quality_flags[duplicated_ids] <- paste0(data$quality_flags[duplicated_ids],
    ifelse(nzchar(data$quality_flags[duplicated_ids]), "|", ""), "duplicate_record")

  eligible <- data$coordinate_status %in% c("valid_source_coordinate", "derived_geocode")
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
#' @param data Annotated equipment data.
#' @return Data frame with deterministic counts and proportions.
#' @export
data_quality_summary <- function(data) {
  category <- ifelse(is.na(data$category) | !nzchar(data$category), "Sem categoria", data$category)
  split_data <- split(seq_len(nrow(data)), category)
  rows <- lapply(names(split_data), function(cat) {
    i <- split_data[[cat]]
    ok <- data$coordinate_status[i] %in% c("valid_source_coordinate", "derived_geocode")
    data.frame(category = cat, n = length(i), coordinate_n = sum(ok),
      coordinate_pct = if (length(i)) 100 * mean(ok) else NA_real_,
      cep_n = sum(!is.na(data$postal_code[i]) & nzchar(data$postal_code[i])), stringsAsFactors = FALSE)
  })
  dplyr::bind_rows(rows)[order(vapply(rows, function(x) -x$n, numeric(1))), , drop = FALSE]
}
