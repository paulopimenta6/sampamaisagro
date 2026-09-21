#!/usr/bin/env Rscript
# Explicit candidate capture, never invoked by tests. Run from the repository root.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Usage: Rscript scripts/capture_v02_baseline.R NEW_OUTPUT_DIRECTORY")
# Find an existing ancestor without creating anything, then reconstruct the target.
# Resolve symlinks again after /.. components can expose a different existing parent.
resolve_capture_target <- function(path) {
  ancestor <- path.expand(path)
  pending <- character()
  dangling <- function(path) {
    link <- Sys.readlink(path)
    !is.na(link) && nzchar(link) && !file.exists(path)
  }
  while (!file.exists(ancestor)) {
    if (dangling(ancestor)) stop("Unresolvable symbolic link in capture destination.")
    parent <- dirname(ancestor)
    if (identical(parent, ancestor)) stop("No existing ancestor for capture destination.")
    pending <- c(basename(ancestor), pending)
    ancestor <- parent
  }
  resolved <- normalizePath(ancestor, winslash = "/", mustWork = TRUE)
  if (length(pending) && !dir.exists(resolved)) stop("Capture parent is not a directory.")
  for (part in pending) {
    resolved <- if (part == "..") dirname(resolved) else if (part == ".") resolved else file.path(resolved, part)
    if (dangling(resolved)) stop("Unresolvable symbolic link in capture destination.")
    if (file.exists(resolved)) resolved <- normalizePath(resolved, winslash = "/", mustWork = TRUE)
  }
  resolved
}
target <- resolve_capture_target(args[[1]])
fixtures <- normalizePath("tests/fixtures/v02", winslash = "/", mustWork = TRUE)
if (identical(target, fixtures) || startsWith(target, paste0(fixtures, "/"))) {
  stop("Capture outside the approved fixtures directory.")
}
if (file.exists(target) && (!dir.exists(target) || file.access(target, 4L) != 0L ||
    length(list.files(target, all.files = TRUE, no.. = TRUE)) > 0L)) {
  stop("Use a new or empty output directory; candidates are never overwritten.")
}
pkgload::load_all(".", quiet = TRUE)
withr::local_collate("C")
source(file.path(fixtures, "load.R"))
work <- tempfile("v02-capture-"); dir.create(work)
config <- v02_config(work, fixtures)
v02_prepare_cep(config, fixtures)
records <- sampamaisrural::validate_equipment(v02_records(fixtures), config)
stopifnot(nrow(records$data) == 7L, nrow(records$eligible) == 3L)
graph <- v02_graph(fixtures)
graphs <- setNames(rep(list(graph), 3L), c("foot", "bicycle", "motorcar"))
origins <- v02_internal("read_origin_file")(file.path(fixtures, "origins.csv"))
resolved <- sampamaisrural::resolve_origins(origins, config)
result <- sampamaisrural::calculate_proximity(resolved$valid, v02_destinations(fixtures),
  graphs, modes = names(graphs), directions = "both", config = config)
# Independent hand-cost oracles must hold before anything is captured.
oracle <- sampamaisrural::calculate_proximity(v02_origin(fixtures), v02_destinations(fixtures, "D"),
  list(motorcar = graph), modes = "motorcar", directions = "both", config = config)
net <- oracle[oracle$distance_family == "network", ]
stopifnot(identical(net$distance_m, c(200, 350, 300, 350)),
  isTRUE(all.equal(net$duration_min[3:4], c(20, 70) / 60)))
batch <- sampamaisrural::process_batch(origins, file.path(work, "batch"),
  v02_destinations(fixtures), graphs, config, list(modes = names(graphs), directions = "both"))
stopifnot(batch$summary$valid_rows == 2L, batch$summary$error_rows == 2L)
dir.create(target, recursive = TRUE, showWarnings = FALSE)
record_fields <- c("equipment_id", "record_version_id", "source_key", "equipment_name",
  "category", "subcategory", "groups", "accessibility", "latitude", "longitude", "coordinate_status")
readr::write_csv(records$data[, record_fields], file.path(target, "records.csv"), na = "")
readr::write_csv(v02_projection(result), file.path(target, "proximity.csv"), na = "")
readr::write_csv(v02_diagnostics(result), file.path(target, "routing.csv"), na = "")
jsonlite::write_json(batch$summary[c("status", "total_rows", "valid_rows", "error_rows")],
  file.path(target, "batch.json"), auto_unbox = TRUE, pretty = TRUE)
inputs <- list.files(fixtures, recursive = TRUE, full.names = TRUE)
inputs <- inputs[!grepl("/expected/", inputs) & !dir.exists(inputs)]
hashes <- setNames(vapply(inputs, v02_internal("sha256_file"), character(1)),
  substring(inputs, nchar(fixtures) + 2L))
code <- list.files("R", full.names = TRUE, pattern = "\\.R$")
code_hashes <- setNames(vapply(code, v02_internal("sha256_file"), character(1)), code)
manifest <- list(reference_commit = trimws(system2("git", c("rev-parse", "HEAD"), stdout = TRUE)),
  synthetic = TRUE, snapshot = "synthetic-v02", raw_records = 8L,
  analytical_records = 7L, spatially_eligible = 3L, tolerance = 1e-8,
  fixture_hashes = as.list(hashes), code_hashes = as.list(code_hashes),
  lc_collate = Sys.getlocale("LC_COLLATE"), r_version = as.character(getRversion()),
  packages = lapply(c("dodgr", "sf", "geosphere", "digest"), function(p)
    list(package = p, version = as.character(utils::packageVersion(p)))),
  spatial_libraries = as.list(sf::sf_extSoftVersion()))
jsonlite::write_json(manifest, file.path(target, "manifest.json"), auto_unbox = TRUE, pretty = TRUE)
message("Candidate baseline written to ", target, "; review independently before approving.")
