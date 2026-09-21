#!/usr/bin/env Rscript
# Explicit synthetic harness; never loads equipment or maps from the real tree.
lib <- Sys.getenv("SAMPA_FIXTURE_LIBRARY")
if (!nzchar(lib)) stop("Set SAMPA_FIXTURE_LIBRARY to the newly installed candidate package library.")
library(sampamaisrural, lib.loc = lib)
fixtures <- normalizePath("tests/fixtures/v02")
source(file.path(fixtures, "load.R"))
root <- tempfile("sampa-browser-fixture-"); dir.create(root)
cfg <- v02_config(root, fixtures)
v02_prepare_cep(cfg, fixtures)
files <- file.path(fixtures, "raw", c("base-completa-sampa-rural.json", "tematico.json", "vazio.json"))
manifest <- data.frame(dataset = c("base", "tematico", "vazio"), format = "json", path = files,
  records = c(8L, 1L, 0L), bytes = file.info(files)$size,
  sha256 = vapply(files, v02_internal("sha256_file"), character(1)))
# A prepared offline installation includes its inventory. Materialize synthetic
# products rather than exposing the real inventory through default paths.
suppressMessages(prepare_equipment_data(manifest, cfg))
graph <- v02_graph(fixtures)
graphs <- setNames(rep(list(graph), 3), c("foot", "bicycle", "motorcar"))
run_app(config = cfg, equipment = v02_quality(fixtures), graphs = graphs,
  host = "127.0.0.1", port = as.integer(Sys.getenv("SAMPA_FIXTURE_PORT", "3955")), launch.browser = FALSE)
