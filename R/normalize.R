canonical_partner_row <- function(x, snapshot_date) {
  value <- function(name) x[[name]] %||% NULL
  lat <- as_number(value("Latitudade") %||% value("Latitude"))
  lon <- as_number(value("Longitude"))
  identity_payload <- list(
    name = collapse_value(value("Nome do Perfil")),
    category = collapse_value(value("Categoria")),
    source = collapse_value(value("Fonte")),
    address = collapse_value(value("Endere\u00e7o comercial")),
    latitude = lat, longitude = lon, snapshot = snapshot_date
  )
  record_id <- digest::digest(identity_payload, algo = "sha256")
  data.frame(
    equipment_id = substr(digest::digest(identity_payload[names(identity_payload) != "snapshot"], algo = "sha256"), 1, 24),
    record_version_id = record_id,
    equipment_name = collapse_value(value("Nome do Perfil")),
    source_database = collapse_value(value("Nome da base de dados")),
    category = collapse_value(value("Categoria")),
    subcategory = collapse_value(value("Subcategorias")),
    qualifications = collapse_value(value("Qualifica\u00e7\u00f5es")),
    description = collapse_value(value("Descri\u00e7\u00e3o")),
    source_name = collapse_value(value("Fonte")),
    address = collapse_value(value("Endere\u00e7o comercial")),
    neighborhood = collapse_value(value("Bairro")),
    district = collapse_value(value("Distrito")),
    zone = collapse_value(value("Zona")),
    postal_code = normalize_cep(collapse_value(value("CEP"))),
    latitude = lat,
    longitude = lon,
    coordinate_origin = "source",
    coordinate_status = NA_character_,
    snapshot_date = snapshot_date,
    source_payload = jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"),
    stringsAsFactors = FALSE
  )
}

#' Normalize an official Sampa+Rural JSON report
#'
#' Direct contact fields remain only in `source_payload` and are not promoted to the
#' analytical columns.
#'
#' @param path Path to a JSON report containing a `partners` array.
#' @param snapshot_date Snapshot identifier.
#' @return Canonical equipment data frame.
#' @export
normalize_sampa_json <- function(path, snapshot_date = basename(dirname(path))) {
  raw <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  partners <- raw$partners
  if (!is.list(partners)) stop("O JSON nao contem o vetor partners esperado: ", path)
  if (!length(partners)) return(demo_equipment()[0, ])
  dplyr::bind_rows(lapply(partners, canonical_partner_row, snapshot_date = snapshot_date))
}

find_complete_snapshot <- function(config) {
  raw_root <- file.path(config$data_dir, "raw")
  if (!dir.exists(raw_root)) return(character())
  candidates <- list.files(raw_root, pattern = "base-completa-sampa-rural\\.json$",
    recursive = TRUE, full.names = TRUE)
  if (!length(candidates)) {
    candidates <- list.files(raw_root, pattern = "base-completa.*\\.json$",
      recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
  }
  candidates[order(file.info(candidates)$mtime, decreasing = TRUE)]
}

#' Load the current processed equipment data
#'
#' Falls back to a clearly marked synthetic data set when no snapshot exists.
#'
#' @param config Project configuration.
#' @param allow_demo Allow the synthetic fallback.
#' @return Equipment data frame.
#' @export
load_equipment_data <- function(config = read_sampa_config(), allow_demo = TRUE) {
  parquet <- file.path(config$data_dir, "processed", "equipment.parquet")
  rds <- file.path(config$data_dir, "processed", "equipment.rds")
  if (file.exists(parquet)) return(as.data.frame(arrow::read_parquet(parquet)))
  if (file.exists(rds)) return(readRDS(rds))
  raw <- find_complete_snapshot(config)
  if (length(raw)) {
    data <- normalize_sampa_json(raw[[1]])
    checked <- validate_equipment(data, config)
    return(checked$data)
  }
  if (allow_demo) return(demo_equipment())
  stop("Nenhum snapshot processado encontrado. Execute scripts/update_data.R.")
}
