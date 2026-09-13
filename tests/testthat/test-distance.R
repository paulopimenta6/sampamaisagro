test_that("geometric metrics obey basic invariants", {
  eq <- demo_equipment()[1:3, ]
  origin <- data.frame(query_id = "o", latitude = eq$latitude[1], longitude = eq$longitude[1], k = 3, radius_m = 1)
  result <- calculate_proximity(origin, eq, graphs = list(), k = 3, radius_m = 1)
  zero <- result[result$equipment_id == eq$equipment_id[1], ]
  expect_true(all(abs(zero$distance_m) < 1e-6))
  wide <- tidyr::pivot_wider(result, id_cols = equipment_id, names_from = metric_id, values_from = distance_m)
  expect_true(all(wide$chebyshev_projected <= wide$euclidean_projected + 1e-6))
  expect_true(all(wide$euclidean_projected <= wide$manhattan_projected + 1e-6))
  expect_true(all(abs(wide$geodesic_karney - wide$geodesic_haversine) / pmax(wide$geodesic_karney, 1) < 0.01))
})

test_that("network paths include mode and objective", {
  skip_if_not_installed("dodgr")
  lines <- sf::st_sf(
    osm_id = c("a", "b"), highway = "residential",
    geometry = sf::st_sfc(
      sf::st_linestring(matrix(c(-46.64, -23.55, -46.63, -23.55), ncol = 2, byrow = TRUE)),
      sf::st_linestring(matrix(c(-46.63, -23.55, -46.62, -23.55), ncol = 2, byrow = TRUE)), crs = 4326)
  )
  graph <- build_network_graphs(lines, "foot")$foot
  eq <- demo_equipment()[1:2, ]
  eq$longitude <- c(-46.63, -46.62); eq$latitude <- -23.55
  origin <- data.frame(query_id = "o", latitude = -23.55, longitude = -46.64, k = 2, radius_m = 5000)
  result <- calculate_proximity(origin, eq, list(foot = graph), k = 2, radius_m = 5000, modes = "foot")
  expect_true(all(c("network_foot_shortest", "network_foot_fastest") %in% result$metric_id))
  expect_true(all(result$duration_min[result$metric_id == "network_foot_fastest"] >= 0))
})
