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
