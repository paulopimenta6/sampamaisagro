#!/usr/bin/env Rscript
# This is an integration test, not a synthetic demonstration. Missing real data fail.
pkgload::load_all(".", quiet = TRUE)
cfg <- read_sampa_config()
target <- file.path(cfg$project_root, "outputs", "validation-real")
dir.create(target, recursive = TRUE, showWarnings = FALSE)
requested <- commandArgs(trailingOnly = TRUE)
if (length(setdiff(requested, cfg$network$modes))) stop("Use apenas foot, bicycle ou motorcar.")
test_modes <- if (length(requested)) requested else cfg$network$modes
sampamaisrural:::atomic_write_json(list(passed = FALSE, status = "running_or_incomplete",
  started_at = sampamaisrural:::utc_now(), requested_modes = test_modes), file.path(target, "evidence.json"))
equipment <- load_equipment_data(cfg, allow_demo = FALSE)
stopifnot(nrow(equipment) > 1000, all(equipment$coordinate_origin == "source"))
inventory <- sampamaisrural:::local_inventory(cfg)
stopifnot(sum(inventory$format == "csv") == 14,
  sum(inventory$format == "json" & inventory$dataset != "catalog") == 14)
for (i in seq_len(nrow(inventory))) {
  stopifnot(file.exists(inventory$path[i]),
    identical(sampamaisrural:::sha256_file(inventory$path[i]), inventory$sha256[i]))
}
# Prohibit the only geocoding/collection HTTP helper during actual analysis.
testthat::local_mocked_bindings(perform_request = function(...) stop("NETWORK FORBIDDEN"),
  .package = "sampamaisrural")
origins <- resolve_origins(data.frame(query_id = c("teste-iquiririm", "teste-se"),
  cep = c("05586001", NA), latitude = c(NA, -23.55008), longitude = c(NA, -46.63408),
  k = c(10, 5), radius_m = c(5000, 1000)), cfg)
stopifnot(nrow(origins$valid) == 2, nrow(origins$errors) == 0,
  abs(origins$valid$latitude[1] - (-23.571872)) < 0.001,
  abs(origins$valid$longitude[1] - (-46.730196)) < 0.001)
geometric <- calculate_proximity(origins$valid, equipment, graphs = list(), modes = character(), config = cfg)
stopifnot(length(unique(geometric$metric_id)) == 5, all(is.finite(geometric$distance_m)))
readr::write_csv(geometric, file.path(target, "geometric-results.csv"))
all_results <- list(geometric)
diagnostics <- list()
timings <- list()
analysis_key <- digest::digest(list(equipment, origins$valid,
  sampamaisrural:::sha256_file("scripts/validate_real_data.R"),
  vapply(list.files("R", full.names = TRUE, pattern = "\\.R$"),
    sampamaisrural:::sha256_file, character(1))), algo = "sha256")
# Load one mode at a time to avoid tripling the peak memory of the routing test.
for (mode in test_modes) {
  message("Validando rede real: ", mode)
  graph_file <- file.path(cfg$data_dir, "processed", paste0("network_", mode, ".rds"))
  stopifnot(file.exists(graph_file))
  key <- digest::digest(list(analysis_key, sampamaisrural:::sha256_file(graph_file), mode), algo = "sha256")
  cache_path <- file.path(target, paste0("validated-", mode, ".rds"))
  cached <- if (file.exists(cache_path)) readRDS(cache_path) else NULL
  if (!is.null(cached) && identical(cached$key, key)) {
    message("Reutilizando teste já aprovado para os mesmos dados, grafo e código: ", mode)
    all_results[[length(all_results) + 1L]] <- cached$result
    diagnostics[[mode]] <- cached$diagnostics
    timings[[mode]] <- cached$timing
    next
  }
  graph <- load_network_graphs(cfg, mode)
  stopifnot(identical(names(graph), mode), nrow(graph[[mode]]) > 1000)
  stopifnot(isTRUE(grepl("^v2:", attr(graph[[mode]], "direction_access_policy"))))
  manifest <- jsonlite::fromJSON(file.path(cfg$data_dir, "processed", "network_manifest.json"))
  stopifnot(identical(attr(graph[[mode]], "source_sha256"), manifest$roads_sha256))
  timing <- system.time(result <- calculate_proximity(origins$valid[1, ], equipment,
    graphs = graph, modes = mode, directions = "both", k = 10, radius_m = 1000, config = cfg))
  routed <- result[result$distance_family == "network", ]
  stopifnot(nrow(routed) > 0, length(unique(routed$metric_id)) == 2,
    length(unique(routed$direction)) == 2, all(routed$distance_m >= 0))
  fastest <- routed[routed$path_objective == "fastest", ]
  stopifnot(all(is.finite(fastest$duration_min)))
  for (direction in unique(fastest$direction)) {
    sorted <- fastest[fastest$direction == direction, ]
    stopifnot(all(diff(sorted$duration_min[order(sorted$rank)]) >= -1e-8))
  }
  # Network paths plus connectors cannot be shorter than the geodesic separation,
  # allowing 1% for spherical edge lengths and numerical/model approximation.
  direct <- geometric[geometric$origin_id == "teste-iquiririm" & geometric$metric_id == "geodesic_karney", ]
  direct_distance <- direct$distance_m[match(routed$equipment_id, direct$equipment_id)]
  stopifnot(all(routed$distance_m >= 0.99 * direct_distance, na.rm = TRUE))
  all_results[[length(all_results) + 1L]] <- routed
  diagnostics[[mode]] <- attr(result, "routing_diagnostics")
  timings[[mode]] <- list(elapsed_seconds = unname(timing["elapsed"]), selected_pairs = nrow(routed))
  sampamaisrural:::atomic_save_rds(list(key = key, result = routed,
    diagnostics = diagnostics[[mode]], timing = timings[[mode]]), cache_path)
  rm(graph, result); gc(verbose = FALSE)
}
if (length(requested)) {
  message("Modos solicitados validados. Execute sem argumentos para consolidar as 11 métricas.")
  quit(status = 0)
}
combined <- dplyr::bind_rows(all_results)
stopifnot(length(unique(combined$metric_id)) == 11)
readr::write_csv(combined, file.path(target, "all-distances.csv"))
readr::write_csv(dplyr::bind_rows(diagnostics), file.path(target, "routing-diagnostics.csv"))
readr::write_csv(sampamaisrural:::proximity_summary(combined), file.path(target, "statistics.csv"))
job_dir <- file.path(target, paste0("batch-", format(Sys.time(), "%Y%m%dT%H%M%S")))
batch <- process_batch("inst/examples/origens-reais.csv", job_dir, equipment,
  graphs = list(), config = cfg, parameters = list(modes = character()))
stopifnot(batch$summary$valid_rows == 2, batch$summary$error_rows == 1)
render_proximity_report(combined, file.path(target, "relatorio-real.html"), origins$valid, equipment, cfg)
ggplot2::ggsave(file.path(target, "mapa-real.png"), create_static_map(geometric, "geodesic_karney"),
  width = 9, height = 7, dpi = 150)
nearest <- geometric[geometric$origin_id == "teste-iquiririm" & geometric$metric_id == "geodesic_karney", ]
evidence <- list(passed = TRUE, tested_at = sampamaisrural:::utc_now(),
  snapshot = unique(equipment$snapshot_date), local_records = nrow(equipment),
  spatially_eligible = nrow(validate_equipment(equipment, cfg)$eligible),
  metric_count = length(unique(combined$metric_id)), network_modes = cfg$network$modes,
  network_timings = timings, nearest = nearest[1:5, c("equipment_name", "distance_m")],
  within_5km_karney = sum(nearest$within_radius), batch = batch$summary,
  http_helper_blocked = TRUE, source_file_count = nrow(inventory))
sampamaisrural:::atomic_write_json(evidence, file.path(target, "evidence.json"))
print(evidence)
capture.output(utils::sessionInfo(), file = file.path(target, "session-info.txt"))
