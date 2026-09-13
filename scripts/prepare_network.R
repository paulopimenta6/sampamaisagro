#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) stop("Uso: Rscript scripts/prepare_network.R arquivo.osm.pbf [limite.gpkg]")
root <- normalizePath(if (file.exists("DESCRIPTION")) "." else "..", mustWork = TRUE)
if (requireNamespace("sampamaisrural", quietly = TRUE)) library(sampamaisrural) else pkgload::load_all(root, quiet = TRUE)
config <- read_sampa_config(file.path(root, "config.yml"))
pbf <- normalizePath(args[[1]], mustWork = TRUE)
boundary <- if (length(args) >= 2L) sf::st_read(args[[2]], quiet = TRUE) else NULL
message("Lendo linhas OSM; esta etapa pode consumir memoria e varios minutos.")
lines <- sampamaisrural:::read_osm_lines(pbf, boundary)
graphs <- build_network_graphs(lines, config$network$modes)
save_network_graphs <- getFromNamespace("save_network_graphs", "sampamaisrural")
save_network_graphs(graphs, config)
metadata <- list(
  built_at = sampamaisrural:::utc_now(), source_file = basename(pbf),
  source_sha256 = sampamaisrural:::sha256_file(pbf),
  modes = names(graphs), edge_counts = vapply(graphs, nrow, integer(1))
)
sampamaisrural:::atomic_write_json(metadata, file.path(config$data_dir, "processed", "network_manifest.json"))
message("Grafos gravados em ", file.path(config$data_dir, "processed"))
