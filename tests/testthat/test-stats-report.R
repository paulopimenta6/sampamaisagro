test_that("hex aggregation conserves equipment counts", {
  eq <- demo_equipment()
  grid <- create_hex_grid(eq, 5000)
  expect_equal(sum(grid$equipment_n), nrow(eq))
})

test_that("map constructors return reusable objects", {
  eq <- demo_equipment()[1:3, ]
  origin <- data.frame(query_id = "o", latitude = -23.55, longitude = -46.63, k = 3, radius_m = 5000)
  result <- calculate_proximity(origin, eq, k = 3, radius_m = 5000)
  expect_s3_class(create_interactive_map(result), "leaflet")
  expect_s3_class(create_static_map(result), "ggplot")
})

test_that("count model reports dispersion and causal caveat", {
  grid <- create_hex_grid(demo_equipment(), 5000)
  fit <- fit_spatial_count_model(grid)
  expect_true(fit$selected_family %in% c("poisson", "negative_binomial"))
  expect_true(is.finite(fit$dispersion))
  expect_match(fit$caveat, "nao sustenta inferencia causal")
})

test_that("HTML report renders", {
  skip_if_not(rmarkdown::pandoc_available())
  eq <- demo_equipment()[1:3, ]
  origin <- data.frame(query_id = "o", latitude = -23.55, longitude = -46.63, k = 3, radius_m = 5000)
  result <- calculate_proximity(origin, eq, k = 3, radius_m = 5000)
  target <- tempfile(fileext = ".html")
  expect_true(file.exists(render_proximity_report(result, target, equipment = eq)))
})

test_that("agreement respects fastest-path ranking rather than distance", {
  a <- data.frame(origin_id = "o", equipment_id = letters[1:3],
    distance_m = c(100, 200, 300), rank = 1:3)
  b <- a
  b$rank <- 3:1
  agreement <- metric_pair_agreement(a, b, k = 1)
  expect_equal(agreement$spearman_rho, -1)
  expect_equal(agreement$kendall_tau, -1)
  expect_equal(agreement$top_k_jaccard, 0)
  expect_equal(agreement$mean_difference_m, 0)
})

test_that("local roads are encoded as one GeoJSON feature", {
  cfg <- read_sampa_config()
  cfg$data_dir <- tempfile("local-roads-")
  dir.create(file.path(cfg$data_dir, "processed"), recursive = TRUE)
  on.exit(unlink(cfg$data_dir, recursive = TRUE))
  xy <- matrix(c(-46.73, -23.57, -46.72, -23.56), ncol = 2, byrow = TRUE)
  roads <- sf::st_sf(geometry = sf::st_sfc(sf::st_linestring(xy),
    sf::st_linestring(xy + 0.001), crs = 4326))
  saveRDS(roads, file.path(cfg$data_dir, "processed", "map_roads.rds"))
  ctx <- load_map_context(cfg)
  geo <- jsonlite::fromJSON(ctx$roads_geojson, simplifyVector = FALSE)
  expect_identical(geo$type, "Feature")
  expect_identical(geo$geometry$type, "MultiLineString")
  expect_length(geo$geometry$coordinates, 2)
  map <- make_leaflet_map(data.frame(), context = ctx)
  methods <- vapply(map$x$calls, function(x) x$method, character(1))
  expect_equal(sum(methods == "addGeoJSON"), 1)
  expect_false("addPolylines" %in% methods)
})
