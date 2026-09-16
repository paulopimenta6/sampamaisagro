web_test_config <- function(path) read_sampa_config(overrides = list(
  data_dir = file.path(path, "data"), jobs_dir = file.path(path, "jobs"),
  reports_dir = file.path(path, "reports")))

web_test_origins <- function() data.frame(query_id = c("one", "two", "bad"),
  latitude = c(-23.55, -23.55, 99), longitude = c(-46.64, -46.63, -46.63),
  k = c(1, 2, 1), radius_m = c(1, 5000, 1))

web_test_graph <- function() build_network_graphs(sf::st_sf(
  osm_id = c("a", "b"), highway = "residential",
  geometry = sf::st_sfc(
    sf::st_linestring(matrix(c(-46.64, -23.55, -46.63, -23.55), ncol = 2, byrow = TRUE)),
    sf::st_linestring(matrix(c(-46.63, -23.55, -46.62, -23.55), ncol = 2, byrow = TRUE)), crs = 4326)), "foot")

test_that("progressive partitions preserve all metrics, row settings and diagnostics", {
  cfg <- web_test_config(withr::local_tempdir())
  equipment <- demo_equipment()[1:2, ]
  equipment$latitude <- -23.55; equipment$longitude <- c(-46.63, -46.62)
  graphs <- web_test_graph()
  pool <- new_web_pool()
  id <- web_submit(pool, web_test_origins(), equipment, graphs, cfg, "foot", "both", "batch")
  path <- pool$jobs[[id]]$dir
  web_job_worker(file.path(path, "request.rds"))
  state <- web_job_read(path)
  expect_equal(state$status, "completed")
  expect_equal(state$errors$query_id, "bad")
  expect_equal(state$errors$row, 3)
  expect_equal(state$completed_units, 4)
  expect_equal(state$total_units, 4)
  parts <- lapply(file.path(path, state$parts), readRDS)
  expect_true(all(parts[[1]]$distance_family == "geometric"))
  expect_true(all(parts[[2]]$distance_family == "geometric"))
  expect_true(all(parts[[3]]$distance_family == "network"))
  expected <- calculate_proximity(resolve_origins(web_test_origins()[1:2, ], cfg)$valid, equipment, graphs,
    modes = "foot", directions = "both", config = cfg)
  actual <- web_job_results(path)
  canonical <- function(x) {
    x <- x[order(x$origin_id, x$metric_id, x$direction, x$equipment_id), ]
    attr(x, "analysis") <- NULL; attr(x, "routing_diagnostics") <- NULL
    attr(x, "missing_network_modes") <- NULL; rownames(x) <- NULL
    x
  }
  expect_equal(canonical(actual), canonical(expected), tolerance = 1e-8)
  diag <- function(x) {
    x <- attr(x, "routing_diagnostics")
    x <- x[order(x$origin_id, x$metric_id, x$routing_status), ]
    rownames(x) <- NULL; x
  }
  expect_equal(diag(actual), diag(expected))
  agreement <- proximity_agreement(actual)
  for (origin in unique(actual$origin_id)) {
    x <- actual[actual$origin_id == origin, ]
    observed <- agreement[agreement$origin_id == origin, ]; rownames(observed) <- NULL
    expect_equal(observed, metric_agreement(x, k = x$selection_k[[1]]))
  }
  exported <- web_export_results(actual, state)
  expect_true(all(exported$analysis_status == "completed"))
  bundle <- web_batch_bundle(path, state)
  manifest <- jsonlite::read_json(file.path(bundle, "manifest.json"))
  expect_true(manifest$complete)
  expect_false(any(grepl("request|input|worker", list.files(bundle))))
  expect_true(all(file.exists(file.path(bundle, unlist(manifest$partitions)))))
})

test_that("missing networks fail visibly without discarding geometry", {
  cfg <- web_test_config(withr::local_tempdir())
  pool <- new_web_pool()
  id <- web_submit(pool, web_test_origins()[1, ], demo_equipment(), NULL,
    cfg, "foot", "both", "single")
  path <- pool$jobs[[id]]$dir
  web_job_worker(file.path(path, "request.rds"))
  state <- web_job_read(path)
  expect_equal(state$status, "failed")
  expect_match(state$stage, "Grafo local ausente")
  expect_equal(state$completed_units, 1)
  expect_equal(state$total_units, 2)
  result <- web_job_results(path)
  expect_length(unique(result$metric_id), 5)
  expect_match(web_job_message(state, result), "parciais")
  expect_equal(attr(result, "analysis")$status, "failed")
})

test_that("invalid origins and duplicate IDs do not produce stale results", {
  cfg <- web_test_config(withr::local_tempdir())
  pool <- new_web_pool()
  raw <- web_test_origins(); raw$query_id[1:2] <- "duplicate"
  id <- web_submit(pool, raw, demo_equipment(), list(), cfg, character(), "both", "batch")
  path <- pool$jobs[[id]]$dir
  web_job_worker(file.path(path, "request.rds"))
  state <- web_job_read(path)
  expect_equal(state$status, "failed")
  expect_equal(sort(unique(state$errors$row)), 1:3)
  expect_equal(nrow(web_job_results(path)), 0)
  expect_equal(length(state$parts), 0)
  expect_true(file.exists(file.path(web_batch_bundle(path, state), "errors.csv")))
})

test_that("a real child works without a project profile or an external worker", {
  cfg <- web_test_config(withr::local_tempdir())
  pool <- new_web_pool()
  id <- web_submit(pool, web_test_origins(), demo_equipment(), list(), cfg, character(), "both", "batch")
  withr::defer(web_stop(pool, id))
  web_poll(pool)
  process <- pool$jobs[[id]]$process
  expect_true(process$is_alive())
  process$wait(30000)
  expect_false(process$is_alive())
  web_poll(pool)
  state <- web_job_read(pool$jobs[[id]]$dir)
  expect_equal(state$status, "completed")
  expect_equal(state$completed_units, 2)
  expect_null(pool$active)
})

test_that("empty filters do not load graphs and still produce a batch manifest", {
  cfg <- web_test_config(withr::local_tempdir())
  pool <- new_web_pool()
  id <- web_submit(pool, web_test_origins()[1, ], demo_equipment()[FALSE, ], NULL,
    cfg, c("foot", "bicycle", "motorcar"), "both", "batch")
  path <- pool$jobs[[id]]$dir
  web_job_worker(file.path(path, "request.rds"))
  state <- web_job_read(path)
  expect_equal(state$status, "completed")
  expect_equal(state$completed_units, 4)
  expect_equal(nrow(web_job_results(path)), 0)
  expect_length(list.files(web_batch_bundle(path, state), pattern = "parquet$"), 4)
})

test_that("interactive geocoding stays offline even with online preparation config", {
  cfg <- web_test_config(withr::local_tempdir())
  cfg$geocoding$offline <- FALSE
  pool <- new_web_pool()
  id <- web_submit(pool, data.frame(cep = "99999999"), demo_equipment(), list(),
    cfg, character(), "both", "single")
  path <- pool$jobs[[id]]$dir
  web_job_worker(file.path(path, "request.rds"))
  state <- web_job_read(path)
  expect_equal(state$status, "failed")
  expect_match(state$stage, "ndice local")
})

test_that("cancellation, queueing, process death and timeout release the slot", {
  cfg <- web_test_config(withr::local_tempdir())
  launch_sleep <- function(path) callr::r_bg(function() Sys.sleep(60),
    user_profile = FALSE, supervise = TRUE, stdout = file.path(path, "worker.log"),
    stderr = file.path(path, "worker-errors.log"))
  pool <- new_web_pool(launch_sleep)
  submit <- function() web_submit(pool, web_test_origins(), demo_equipment(), list(), cfg, character(), "both", "batch")
  first <- submit(); second <- submit()
  withr::defer({ web_stop(pool, first); web_stop(pool, second) })
  web_poll(pool)
  expect_equal(pool$active, first)
  expect_null(pool$jobs[[second]]$process)
  web_stop(pool, first)
  expect_false(pool$jobs[[first]]$process$is_alive())
  expect_equal(web_job_read(pool$jobs[[first]]$dir)$status, "cancelled")
  web_poll(pool)
  expect_equal(pool$active, second)
  pool$jobs[[second]]$process$kill()
  pool$jobs[[second]]$process$wait(1000)
  web_poll(pool)
  expect_equal(web_job_read(pool$jobs[[second]]$dir)$status, "failed")
  expect_null(pool$active)
  third <- submit()
  withr::defer(web_stop(pool, third))
  web_poll(pool)
  state <- web_job_read(pool$jobs[[third]]$dir)
  state$updated_at <- as.numeric(Sys.time()) - 1000
  atomic_save_rds(state, file.path(pool$jobs[[third]]$dir, "progress.rds"))
  web_poll(pool)
  expect_equal(web_job_read(pool$jobs[[third]]$dir)$status, "failed")
  expect_match(web_job_read(pool$jobs[[third]]$dir)$stage, "Limite de tempo")
  expect_false(pool$jobs[[third]]$process$is_alive())
  fourth <- submit()
  web_stop(pool, fourth)
  web_poll(pool)
  expect_null(pool$jobs[[fourth]]$process)
})
