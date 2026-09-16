#!/usr/bin/env Rscript
pkgload::load_all(".", quiet = TRUE)
config <- read_sampa_config()
args <- commandArgs(trailingOnly = TRUE)
# Existing snapshots can be rebuilt entirely offline, without redownloading.
manifest <- if (length(args)) audit_local_snapshot(args[[1]], config) else
  collect_sampa_data(config, include_terms = FALSE)
prepare_equipment_data(manifest, config)
