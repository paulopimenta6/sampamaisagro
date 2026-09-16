#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
parse_arg <- function(name, default = NULL) {
  hit <- args[startsWith(args, paste0("--", name, "="))]
  if (!length(hit)) default else sub(paste0("^--", name, "="), "", hit[[1]])
}
input <- parse_arg("input")
output <- parse_arg("output", file.path("outputs", paste0("batch-", format(Sys.time(), "%Y%m%d-%H%M%S"))))
if (is.null(input)) stop("Informe --input=arquivo.csv [--output=diretorio] [--k=10] [--radius=5000].")
root <- normalizePath(if (file.exists("DESCRIPTION")) "." else "..", mustWork = TRUE)
pkgload::load_all(root, quiet = TRUE)
config <- read_sampa_config(file.path(root, "config.yml"))
parameters <- list(
  directions = parse_arg("direction", "origin_to_equipment"),
  modes = strsplit(parse_arg("modes", paste(config$network$modes, collapse = ",")), ",", fixed = TRUE)[[1]]
)
if (!is.null(parse_arg("k"))) parameters$k <- as.numeric(parse_arg("k"))
if (!is.null(parse_arg("radius"))) parameters$radius_m <- as.numeric(parse_arg("radius"))
result <- process_batch(input, output, load_equipment_data(config), load_network_graphs(config),
  config, parameters, resume = TRUE,
  progress_callback = function(done, total, message) message(message))
message("Saida: ", normalizePath(result$output_dir, mustWork = FALSE))
