test_that("synthetic directed costs distinguish objectives, directions and disconnection", {
  cfg <- v02_test_config(); v02_forbid_http()
  graph <- v02_graph(v02_fixtures)
  for (mode in c("foot", "bicycle", "motorcar")) {
    x <- calculate_proximity(v02_origin(v02_fixtures), v02_destinations(v02_fixtures),
      setNames(list(graph), mode), modes = mode, directions = "both", config = cfg)
    d <- x[x$distance_family == "network" & x$equipment_id == "synthetic-D", ]
    expect_equal(d$distance_m, c(200, 350, 300, 350), tolerance = 1e-8)
    expect_true(all(is.na(d$duration_min[1:2])))
    expect_equal(d$duration_min[3:4], c(20, 70) / 60, tolerance = 1e-8)
    fastest <- x[x$path_objective %in% "fastest" & x$direction == "origin_to_equipment", ]
    expect_equal(fastest$equipment_id, c("synthetic-D", "synthetic-F", "synthetic-B"))
    expect_false(any(x$equipment_id == "synthetic-U" & x$distance_family == "network"))
    for (direction in c("origin_to_equipment", "equipment_to_origin")) {
      single <- calculate_proximity(v02_origin(v02_fixtures), v02_destinations(v02_fixtures),
        setNames(list(graph), mode), modes = mode, directions = direction, config = cfg)
      diag <- attr(single, "routing_diagnostics")
      expect_equal(diag$n[diag$routing_status == "unreachable"], c(1L, 1L))
    }
  }
})

test_that("snapping thresholds and connectors remain explicit for origin and destination", {
  cfg <- v02_test_config(); v02_forbid_http()
  graph <- v02_graph(v02_fixtures)
  origin <- v02_origin(v02_fixtures); origin$origin_id <- origin$query_id
  eq <- v02_destinations(v02_fixtures, rep("D", 5))
  eq$equipment_id <- paste0("snap-", 1:5)
  distances <- c(0, 250, 250.001, 1000, 1000.001)
  matches <- list(origin = list(id = "A", distance = 0), equipment = list(id = rep("D", 5), distance = distances))
  x <- route_one_direction(graph, origin, eq, "motorcar", "fastest", "origin_to_equipment",
    10, 10000, 250, 1000, 30, matches)
  expect_equal(x$routing_status, c("ok", "ok", "snap_warning", "snap_warning", "snap_excluded"))
  expect_equal(x$distance_m[1:4], 300 + distances[1:4])
  expect_equal(x$duration_min[1:4], 20 / 60 + distances[1:4] / 500)
  expect_true(is.na(x$distance_m[5]) && !x$selected[5])
  matches$origin$distance <- 1000.001
  y <- route_one_direction(graph, origin, eq, "motorcar", "shortest", "origin_to_equipment",
    10, 10000, 250, 1000, 30, matches)
  expect_true(all(y$routing_status == "snap_excluded"))
  # Also exercise actual point matching, not only injected distances.
  eq <- v02_destinations(v02_fixtures, c("D", "D"))
  eq$equipment_id <- eq$record_version_id <- c("warning", "excluded")
  eq$latitude <- eq$latitude - c(0.004, 0.015)
  actual <- calculate_proximity(v02_origin(v02_fixtures), eq, list(motorcar = graph),
    modes = "motorcar", config = cfg)
  diag <- attr(actual, "routing_diagnostics")
  expect_true(all(c("snap_warning", "snap_excluded") %in% diag$routing_status))
})
