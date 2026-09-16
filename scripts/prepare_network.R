#!/usr/bin/env Rscript
pkgload::load_all(".", quiet = TRUE)
args <- commandArgs(trailingOnly = TRUE)
cfg <- read_sampa_config()
if (!length(args) || args[1] == "--offline") {
  prepare_offline_maps(cfg, download = !("--offline" %in% args))
} else {
  # Advanced: supply a custom OSM PBF and optional study polygon.
  pbf <- normalizePath(args[[1]], mustWork = TRUE)
  boundary <- if (length(args) >= 2L) sf::st_read(args[[2]], quiet = TRUE) else NULL
  lines <- sampamaisrural:::read_osm_lines(pbf, boundary)
  graphs <- build_network_graphs(lines, cfg$network$modes)
  sampamaisrural:::save_network_graphs(graphs, cfg)
  sampamaisrural:::atomic_write_json(list(source_file = basename(pbf),
    sha256 = sampamaisrural:::sha256_file(pbf), built_at = sampamaisrural:::utc_now(),
    modes = names(graphs)), file.path(cfg$data_dir, "processed", "network_manifest.json"))
}
