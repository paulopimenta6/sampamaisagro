#!/usr/bin/env Rscript
# Reuse the parsed local sf cache. No network and no re-parsing of the large JSON.
pkgload::load_all(".", quiet = TRUE)
cfg <- read_sampa_config()
requested <- commandArgs(trailingOnly = TRUE)
if (length(setdiff(requested, cfg$network$modes))) stop("Use apenas foot, bicycle ou motorcar.")
modes <- if (length(requested)) requested else cfg$network$modes
path <- file.path(cfg$data_dir, "processed", "osm_lines.rds")
lines <- readRDS(path)
manifest_path <- file.path(cfg$data_dir, "processed", "network_manifest.json")
manifest <- jsonlite::fromJSON(manifest_path, simplifyVector = FALSE)
for (mode in modes) {
  graph_path <- file.path(cfg$data_dir, "processed", paste0("network_", mode, ".rds"))
  # An explicit mode rebuilds directly, avoiding a multi-minute read of the old graph.
  if (!length(requested) && file.exists(graph_path)) {
    existing <- readRDS(graph_path)
    up_to_date <- isTRUE(grepl("^v2:", attr(existing, "direction_access_policy"))) &&
      identical(attr(existing, "source_sha256"), manifest$roads_sha256)
    if (up_to_date) {
      message("Preservando grafo já atualizado: ", mode)
      manifest[[paste0(mode, "_edges")]] <- nrow(existing)
      manifest[[paste0(mode, "_policy")]] <- attr(existing, "direction_access_policy")
      sampamaisrural:::atomic_write_json(manifest, manifest_path)
      rm(existing); gc(verbose = FALSE)
      next
    }
    rm(existing); gc(verbose = FALSE)
  }
  message("Reconstruindo ", mode, " com regras explícitas de sentido e acesso")
  g <- build_network_graphs(lines, mode)
  attr(g[[1]], "source_sha256") <- manifest$roads_sha256
  attr(g[[1]], "coverage_bbox") <- unlist(manifest$coverage)
  sampamaisrural:::save_network_graphs(g, cfg)
  manifest[[paste0(mode, "_edges")]] <- nrow(g[[1]])
  manifest[[paste0(mode, "_policy")]] <- attr(g[[1]], "direction_access_policy")
  sampamaisrural:::atomic_write_json(manifest, manifest_path)
  rm(g); gc(verbose = FALSE)
}
manifest$rebuilt_at <- sampamaisrural:::utc_now()
if (all(vapply(cfg$network$modes, function(mode)
    isTRUE(grepl("^v2:", manifest[[paste0(mode, "_policy")]])), logical(1)))) {
  manifest$direction_access_policy <- "v2: reversed -1; foot bidirectional; roundabouts; explicit no/private excluded; variable oneway excluded for vehicles"
}
sampamaisrural:::atomic_write_json(manifest, manifest_path)
