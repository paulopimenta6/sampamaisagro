`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0L || (length(x) == 1L && is.na(x))) y else x
}

project_root <- function(start = getwd()) {
  current <- normalizePath(start, mustWork = FALSE)
  repeat {
    if (file.exists(file.path(current, "DESCRIPTION"))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) return(normalizePath(start, mustWork = FALSE))
    current <- parent
  }
}

deep_merge <- function(base, override) {
  if (!is.list(base) || !is.list(override)) return(override)
  for (nm in names(override)) {
    base[[nm]] <- if (nm %in% names(base)) deep_merge(base[[nm]], override[[nm]]) else override[[nm]]
  }
  base
}

#' Read the project configuration
#'
#' @param path Optional YAML path. Defaults to `config.yml` in the project.
#' @param overrides Named list recursively merged into the configuration.
#' @return A named configuration list with normalized project paths.
#' @export
read_sampa_config <- function(path = NULL, overrides = list()) {
  root <- project_root()
  default_path <- system.file("config", "default.yml", package = "sampamaisrural")
  if (!nzchar(default_path)) default_path <- file.path(root, "inst", "config", "default.yml")
  cfg <- yaml::read_yaml(default_path)
  local_path <- path %||% file.path(root, "config.yml")
  if (file.exists(local_path)) {
    local_cfg <- yaml::read_yaml(local_path)
    if (!is.null(local_cfg$default)) local_cfg <- local_cfg$default
    cfg <- deep_merge(cfg, local_cfg)
  }
  cfg <- deep_merge(cfg, overrides)
  cfg$project_root <- root
  cfg$data_dir <- normalize_project_path(cfg$data_dir, root)
  cfg$jobs_dir <- normalize_project_path(cfg$jobs_dir, root)
  cfg$reports_dir <- normalize_project_path(cfg$reports_dir, root)
  cfg
}

normalize_project_path <- function(path, root = project_root()) {
  if (grepl("^(/|[A-Za-z]:)", path)) return(normalizePath(path, mustWork = FALSE))
  normalizePath(file.path(root, path), mustWork = FALSE)
}

ensure_project_dirs <- function(config) {
  dirs <- c(
    config$data_dir,
    file.path(config$data_dir, "raw"),
    file.path(config$data_dir, "processed"),
    file.path(config$data_dir, "cache", "cep"),
    file.path(config$data_dir, "osm"),
    config$jobs_dir,
    config$reports_dir
  )
  invisible(vapply(dirs, dir.create, logical(1), recursive = TRUE, showWarnings = FALSE))
}

utc_now <- function() format(Sys.time(), tz = "UTC", usetz = TRUE)

slugify <- function(x) {
  x <- iconv(x, to = "ASCII//TRANSLIT")
  x <- tolower(x)
  x <- gsub("[^a-z0-9]+", "-", x)
  gsub("(^-|-$)", "", x)
}

sha256_file <- function(path) digest::digest(file = path, algo = "sha256", serialize = FALSE)

atomic_save_rds <- function(object, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- tempfile(pattern = ".atomic-", tmpdir = dirname(path), fileext = ".rds")
  on.exit(unlink(tmp), add = TRUE)
  saveRDS(object, tmp)
  if (!file.rename(tmp, path)) stop("Nao foi possivel gravar atomicamente: ", path)
  invisible(path)
}

atomic_write_json <- function(object, path, pretty = TRUE) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- tempfile(pattern = ".atomic-", tmpdir = dirname(path), fileext = ".json")
  on.exit(unlink(tmp), add = TRUE)
  jsonlite::write_json(object, tmp, pretty = pretty, auto_unbox = TRUE, null = "null", na = "null")
  if (!file.rename(tmp, path)) stop("Nao foi possivel gravar atomicamente: ", path)
  invisible(path)
}

collapse_value <- function(x) {
  if (is.null(x) || length(x) == 0L) return(NA_character_)
  if (is.list(x)) x <- unlist(x, recursive = TRUE, use.names = FALSE)
  x <- as.character(x)
  x <- x[!is.na(x) & nzchar(trimws(x))]
  if (!length(x)) NA_character_ else paste(unique(x), collapse = " | ")
}

as_number <- function(x) {
  if (is.null(x) || length(x) == 0L || identical(x, "")) return(NA_real_)
  suppressWarnings(as.numeric(gsub(",", ".", as.character(x), fixed = TRUE)))
}

normalize_cep <- function(x) {
  y <- gsub("[^0-9]", "", as.character(x %||% ""))
  ifelse(nchar(y) == 8L, y, NA_character_)
}

empty_chr <- function(n) rep(NA_character_, n)

#' Synthetic equipment used only for demonstrations and tests
#'
#' @return A 12-row data frame clearly marked as synthetic.
#' @export
demo_equipment <- function() {
  data.frame(
    equipment_id = sprintf("demo-%02d", 1:12),
    record_version_id = sprintf("demo-%02d", 1:12),
    equipment_name = c("Horta Parelheiros", "Feira Capela do Socorro", "Produtor Marsilac",
      "Mercado Santo Amaro", "Iniciativa Grajau", "Turismo Borore", "Horta Sao Mateus",
      "Feira Pinheiros", "Produtor Tremembe", "Mercado Lapa", "Iniciativa Penha", "Turismo Cantareira"),
    category = rep(c("Agricultura", "Mercados", "Iniciativas", "Turismo e Vivencia Rural"), 3),
    subcategory = NA_character_,
    source_name = "Dados sinteticos para demonstracao",
    address = NA_character_, district = NA_character_, zone = NA_character_, postal_code = NA_character_,
    latitude = c(-23.835, -23.720, -23.930, -23.650, -23.755, -23.775, -23.585, -23.565, -23.455, -23.525, -23.525, -23.445),
    longitude = c(-46.710, -46.700, -46.705, -46.700, -46.675, -46.650, -46.480, -46.690, -46.620, -46.700, -46.530, -46.630),
    coordinate_origin = "synthetic",
    coordinate_status = "valid_source_coordinate",
    snapshot_date = "demo",
    stringsAsFactors = FALSE
  )
}
