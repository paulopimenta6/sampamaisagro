#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
once <- "--once" %in% args
root <- normalizePath(if (file.exists("DESCRIPTION")) "." else "..", mustWork = TRUE)
if (requireNamespace("sampamaisrural", quietly = TRUE)) library(sampamaisrural) else pkgload::load_all(root, quiet = TRUE)
config <- read_sampa_config(file.path(root, "config.yml"))
equipment <- load_equipment_data(config)
graphs <- load_network_graphs(config)
sampamaisrural:::cleanup_expired_jobs(config)
repeat {
  outcome <- run_worker_once(config, equipment, graphs)
  if (!is.null(outcome)) sampamaisrural:::cleanup_expired_jobs(config)
  if (once) break
  if (is.null(outcome)) Sys.sleep(3)
}
