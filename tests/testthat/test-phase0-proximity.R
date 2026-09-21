test_that("v02 baseline preserves all five geometric metrics and selected results", {
  cfg <- v02_test_config(); v02_forbid_http(); v02_prepare_cep(cfg, v02_fixtures)
  origins <- resolve_origins(read_origin_file(file.path(v02_fixtures, "origins.csv")), cfg)
  graphs <- setNames(rep(list(v02_graph(v02_fixtures)), 3), c("foot", "bicycle", "motorcar"))
  result <- calculate_proximity(origins$valid, v02_destinations(v02_fixtures), graphs,
    modes = names(graphs), directions = "both", config = cfg)
  expected <- as.data.frame(readr::read_csv(file.path(v02_fixtures, "expected", "proximity.csv"),
    col_types = readr::cols(origin_cep = readr::col_character()), show_col_types = FALSE))
  expect_equal(v02_projection(result), expected, tolerance = 1e-8)
  diagnostic <- as.data.frame(readr::read_csv(file.path(v02_fixtures, "expected", "routing.csv"), show_col_types = FALSE))
  expect_equal(v02_diagnostics(result), diagnostic)
  expect_equal(length(unique(result$metric_id[result$distance_family == "geometric"])), 5L)
  expect_true(all(result$selection_radius_m[result$origin_id == "cep"] == 1))
  expect_true(all(result$origin_cep[result$origin_id == "cep"] == "00000042"))
  expect_true(all(result$geocode_source[result$origin_id == "cep"] == "Synthetic fixture only"))
  eq <- v02_destinations(v02_fixtures, "A")
  zero <- calculate_proximity(v02_origin(v02_fixtures), eq, modes = character(), config = cfg)
  expect_true(all(abs(zero$distance_m) < 1e-6))
  x <- geometric_distance_matrix(-46.712345, -23.612345, v02_destinations(v02_fixtures))
  expect_true(all(x[, "chebyshev_projected"] <= x[, "euclidean_projected"] + 1e-6))
  expect_true(all(x[, "euclidean_projected"] <= x[, "manhattan_projected"] + 1e-6))
})

test_that("radius OR top-k and fastest time ranking retain the four cases", {
  x <- data.frame(equipment_id = letters[1:4], distance_m = c(100, 300, 50, 400),
    duration_min = 1:4, path_objective = "fastest")
  ranked <- rank_distance_rows(x, k = 2, radius_m = 150)
  expect_equal(ranked$selected, c(TRUE, TRUE, TRUE, FALSE))
  expect_equal(ranked$within_radius, c(TRUE, FALSE, TRUE, FALSE))
  expect_equal(ranked$rank, 1:4)
  x$duration_min <- c(2, 1, 3, 4)
  ranked <- rank_distance_rows(x, k = 1, radius_m = 1)
  expect_equal(ranked$equipment_id[ranked$selected], "b")
  x$path_objective <- "shortest"
  expect_equal(rank_distance_rows(x, 1, 1)$equipment_id[1], "c")
  x$distance_m <- 100; x$equipment_id <- rev(letters[1:4])
  expect_equal(rank_distance_rows(x, 1, 100)$equipment_id, letters[1:4])
  expect_true(all(rank_distance_rows(x, 1, 100)$selected))
})
