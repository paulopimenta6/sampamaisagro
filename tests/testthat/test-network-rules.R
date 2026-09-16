test_that("reverse one-way, foot direction and access restrictions are explicit", {
  lines <- sf::st_sf(osm_id = c("reverse", "closed"), highway = "residential",
    oneway = c("-1", "no"), access = c(NA, "private"),
    geometry = sf::st_sfc(
      sf::st_linestring(matrix(c(-46.64,-23.55,-46.63,-23.55), ncol=2,byrow=TRUE)),
      sf::st_linestring(matrix(c(-46.63,-23.55,-46.62,-23.55), ncol=2,byrow=TRUE)), crs=4326))
  graphs <- build_network_graphs(lines, c("foot", "motorcar"))
  car <- graphs$motorcar
  expect_false("closed" %in% car$way_id)
  expect_true(all(car$from_lon > car$to_lon))
  expect_true(any(graphs$foot$from_lon < graphs$foot$to_lon))
  expect_true(any(graphs$foot$from_lon > graphs$foot$to_lon))
  expect_equal(car$d_weighted, car$d)
  expect_equal(car$time_weighted, car$time)
})

test_that("disconnected destinations remain in routing diagnostics", {
  lines <- sf::st_sf(osm_id=c("one","island"),highway="residential",
    geometry=sf::st_sfc(
      sf::st_linestring(matrix(c(-46.64,-23.55,-46.63,-23.55),ncol=2,byrow=TRUE)),
      sf::st_linestring(matrix(c(-46.62,-23.55,-46.61,-23.55),ncol=2,byrow=TRUE)),crs=4326))
  graph <- build_network_graphs(lines,"foot")
  eq <- demo_equipment()[1:2, ]; eq$latitude <- -23.55; eq$longitude <- c(-46.63,-46.61)
  origin <- data.frame(latitude=-23.55,longitude=-46.64)
  result <- calculate_proximity(origin,eq,graph,modes="foot",radius_m=10000)
  diag <- attr(result,"routing_diagnostics")
  expect_true(any(diag$routing_status=="unreachable" & diag$n==1))
  expect_false(any(result$equipment_id==eq$equipment_id[2] & result$distance_family=="network"))
})
