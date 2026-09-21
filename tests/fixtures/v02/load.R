# Test infrastructure only. No real data or network are consulted.
v02_internal <- function(name) get(name, envir = asNamespace("sampamaisrural"))

v02_config <- function(root, fixtures) {
  overrides <- yaml::read_yaml(file.path(fixtures, "config.yml"))
  overrides$data_dir <- file.path(root, "data")
  overrides$jobs_dir <- file.path(root, "jobs")
  overrides$reports_dir <- file.path(root, "reports")
  cfg <- sampamaisrural::read_sampa_config(path = file.path(fixtures, "config.yml"), overrides = overrides)
  cfg$project_root <- normalizePath(root, mustWork = TRUE)
  cfg
}

v02_records <- function(fixtures) {
  withr::local_collate("C")
  raw <- sampamaisrural::normalize_sampa_json(
    file.path(fixtures, "raw", "base-completa-sampa-rural.json"), "synthetic-v02")
  v02_internal("classify_equipment")(raw[!duplicated(raw$equipment_id), , drop = FALSE])
}

v02_quality <- function(fixtures) v02_records(fixtures)[c(1, 2, 3, 6), , drop = FALSE]

v02_graph <- function(fixtures) {
  vertices <- utils::read.csv(file.path(fixtures, "network-vertices.csv"), stringsAsFactors = FALSE)
  edges <- utils::read.csv(file.path(fixtures, "network-edges.csv"), stringsAsFactors = FALSE)
  v02_graph_from_tables(vertices, edges)
}

v02_graph_from_tables <- function(vertices, edges) {
  from <- match(edges$from_id, vertices$id)
  to <- match(edges$to_id, vertices$id)
  stopifnot(!anyNA(from), !anyNA(to))
  data.frame(edge_id = as.character(seq_len(nrow(edges))),
    from_id = as.character(edges$from_id), from_lon = vertices$longitude[from],
    from_lat = vertices$latitude[from], to_id = as.character(edges$to_id),
    to_lon = vertices$longitude[to], to_lat = vertices$latitude[to],
    d = edges$d, d_weighted = edges$d, time = edges$time,
    time_weighted = edges$time, stringsAsFactors = FALSE)
}

v02_destinations <- function(fixtures, ids = c("B", "D", "F", "U")) {
  vertices <- utils::read.csv(file.path(fixtures, "network-vertices.csv"), stringsAsFactors = FALSE)
  vertices <- vertices[match(ids, vertices$id), , drop = FALSE]
  data.frame(equipment_id = paste0("synthetic-", ids), record_version_id = paste0("v02-", ids),
    equipment_name = paste("Destino sintetico", ids), category = "Fixture",
    latitude = vertices$latitude, longitude = vertices$longitude,
    postal_code = NA_character_, snapshot_date = "synthetic-v02", stringsAsFactors = FALSE)
}

v02_origin <- function(fixtures, id = "A") {
  vertex <- utils::read.csv(file.path(fixtures, "network-vertices.csv"), stringsAsFactors = FALSE)
  vertex <- vertex[vertex$id == id, ]
  data.frame(query_id = paste0("origin-", id), latitude = vertex$latitude,
    longitude = vertex$longitude, k = 10L, radius_m = 1000)
}

v02_prepare_cep <- function(config, fixtures) {
  v02_internal("ensure_project_dirs")(config)
  cep <- utils::read.csv(file.path(fixtures, "cep.csv"), colClasses = c(cep = "character"))
  attr(cep, "cache_schema") <- 2L
  saveRDS(cep, file.path(config$data_dir, "cache", "cep", paste0(cep$cep, ".rds")))
  invisible(cep)
}

v02_projection <- function(x) {
  fields <- intersect(c("origin_id", "equipment_id", "metric_id", "direction", "mode",
    "path_objective", "distance_m", "duration_min", "origin_snap_m", "equipment_snap_m",
    "rank", "within_radius", "selected", "routing_status", "selection_k", "selection_radius_m",
    "origin_cep", "geocode_source", "geocode_precision", "geocoded_at"), names(x))
  out <- as.data.frame(x[, fields, drop = FALSE])
  for (nm in setdiff(names(attributes(out)), c("names", "row.names", "class"))) attr(out, nm) <- NULL
  if (nrow(out)) out <- out[do.call(order, out[intersect(
    c("origin_id", "metric_id", "direction", "equipment_id"), names(out))]), , drop = FALSE]
  rownames(out) <- NULL
  out
}

v02_diagnostics <- function(x) {
  x <- attr(x, "routing_diagnostics")
  if (is.null(x)) return(data.frame())
  x <- x[order(x$origin_id, x$metric_id, x$routing_status), , drop = FALSE]
  rownames(x) <- NULL
  x
}
