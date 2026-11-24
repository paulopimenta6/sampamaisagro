areal_fixture <- function() {
  cells <- sf::st_make_grid(sf::st_bbox(c(xmin = 0, ymin = 0, xmax = 3, ymax = 3),
    crs = sf::st_crs(31983)), n = c(3, 3), square = TRUE)
  grid <- sf::st_sf(hex_id = paste0("cell-", 1:9), equipment_n = 0:8, geometry = cells)
  grid$area_km2 <- as.numeric(sf::st_area(grid)) / 1e6
  grid$density_km2 <- grid$equipment_n / grid$area_km2
  grid
}

fixed_domain_fixture <- function() {
  anchor <- data.frame(longitude = -46.63, latitude = -23.55)
  point <- sf::st_as_sf(anchor, coords = c("longitude", "latitude"), crs = 4326)
  xy <- sf::st_coordinates(sf::st_transform(point, 31983))[1, ]
  boundary <- sf::st_as_sf(sf::st_as_sfc(sf::st_bbox(c(xmin = unname(xy[1]),
    ymin = unname(xy[2]), xmax = unname(xy[1]) + 6500, ymax = unname(xy[2]) + 5500),
    crs = sf::st_crs(31983))))
  offsets <- data.frame(x = xy[1] + c(100, 110, 120, 1300, 3400, 6200),
    y = xy[2] + c(100, 110, 120, 1700, 2200, 5200))
  other_points <- sf::st_transform(sf::st_as_sf(offsets, coords = c("x", "y"), crs = 31983), 4326)
  other_xy <- sf::st_coordinates(other_points)
  equipment <- rbind(anchor, data.frame(longitude = other_xy[, 1], latitude = other_xy[, 2]))
  list(equipment = equipment, boundary = boundary)
}

test_that("global Moran requires sf polygons a CRS and an explicit numeric variable", {
  skip_if_not_installed("spdep")
  grid <- areal_fixture()
  expect_error(global_moran(sf::st_drop_geometry(grid), "equipment_n"), "sf poligonal")
  points <- grid
  sf::st_geometry(points) <- sf::st_centroid(sf::st_geometry(grid))
  expect_error(global_moran(points, "equipment_n"), "poligonos")
  expect_error(global_moran(grid[0, ], "equipment_n"), "celulas territoriais")
  no_crs <- sf::st_set_crs(grid, NA)
  expect_error(global_moran(no_crs, "equipment_n"), "CRS")
  expect_error(global_moran(grid), "value_col explicitamente")
  expect_error(global_moran(grid, "absent"), "variavel existente")
  grid$labels <- letters[1:9]
  expect_error(global_moran(grid, "labels"), "numerica")
  invalid <- grid
  sf::st_geometry(invalid)[[1]] <- sf::st_polygon(list(rbind(c(0, 0), c(1, 1), c(1, 0), c(0, 1), c(0, 0))))
  expect_error(global_moran(invalid, "equipment_n"), "poligonos validos")
  empty_polygon <- grid
  sf::st_geometry(empty_polygon)[[1]] <- sf::st_polygon()
  expect_error(global_moran(empty_polygon, "equipment_n"), "poligonos validos")
})

test_that("nonfinite values are rejected without deleting cells or imputing zeros", {
  skip_if_not_installed("spdep")
  for (value in c(NA_real_, NaN, Inf, -Inf)) {
    grid <- areal_fixture()
    grid$equipment_n[2] <- value
    original <- grid
    expect_error(global_moran(grid, "equipment_n", nsim = 19L), "nenhuma celula foi removida ou imputada")
    expect_identical(grid, original)
  }
  constant <- areal_fixture()
  constant$equipment_n <- 0L
  expect_error(global_moran(constant, "equipment_n", nsim = 19L), "variacao")
})

test_that("Queen binary W and observed Moran have manually checkable values", {
  skip_if_not_installed("spdep")
  grid <- areal_fixture()
  original <- grid
  result <- global_moran(grid, "equipment_n", nsim = 19L, seed = 11L)
  expect_identical(grid, original)
  expect_identical(result$value_col, "equipment_n")
  expect_equal(result$n_cells, 9L)
  expect_equal(result$n_zero, 1L)
  expect_equal(result$n_islands, 0L)
  expect_identical(result$neighbour_rule, "queen")
  expect_identical(result$style, "B")
  expect_s3_class(result$listw, "listw")
  expect_equal(spdep::card(result$listw$neighbours), c(3, 5, 3, 5, 8, 5, 3, 5, 3))
  expect_true(all(unlist(result$listw$weights) == 1))
  expect_equal(spdep::Szero(result$listw), 40)
  # For x = 0:8: sum(z^2) = 60, sum_ij(w_ij*z_i*z_j) = 80.
  expect_equal(result$moran_i, 9 / 40 * 80 / 60)
  expect_true(is.finite(result$moran_i))
  expect_gte(result$pseudo_p, 0)
  expect_lte(result$pseudo_p, 1)
  expect_identical(result$cell_ids, grid$hex_id)
  expect_identical(result$nsim, 19L)
  expect_identical(result$seed, 11L)
  expect_identical(result$alternative, "two.sided")
  expect_identical(formals(global_moran)$nsim, 999L)
  expect_true("global_moran" %in% getNamespaceExports("sampamaisrural"))
})

test_that("the permutation distribution excludes the observed value and is inspectable", {
  skip_if_not_installed("spdep")
  result <- global_moran(areal_fixture(), "equipment_n", nsim = 19L, seed = 11L)
  expect_s3_class(result$test, "htest")
  expect_s3_class(result$test, "mc.sim")
  expect_length(result$test$res, 20L)
  expect_length(result$permutation_values, 19L)
  expect_identical(result$permutation_values, result$test$res[1:19])
  expect_identical(result$moran_i, unname(result$test$statistic))
  expect_equal(result$test$res[20], result$moran_i)
  expect_identical(result$pseudo_p, result$test$p.value)
  expect_equal(result$permutation_mean, mean(result$test$res[1:19]))
  expect_equal(result$permutation_sd, stats::sd(result$test$res[1:19]))
  expect_equal(result$rng_kind, RNGkind())
  expect_identical(result$spdep_version, as.character(utils::packageVersion("spdep")))
})

test_that("small maps reject degenerate nulls but retain informative permutations", {
  skip_if_not_installed("spdep")
  cells <- sf::st_make_grid(sf::st_bbox(c(xmin = 0, ymin = 0, xmax = 2, ymax = 2),
    crs = sf::st_crs(31983)), n = c(2, 2), square = TRUE)
  grid <- sf::st_sf(equipment_n = 0:3, geometry = cells)
  withr::local_seed(1234)
  original_seed <- .Random.seed
  # Queen links all four cells: I = -1/3 under every permutation, in B or W.
  for (style in c("B", "W")) {
    expect_error(global_moran(grid, "equipment_n", style = style, nsim = 19L, seed = 11L),
      "distribuicao nula de Moran e degenerada")
    expect_identical(.Random.seed, original_seed)
  }
  # The same four cells with Rook contiguity have an informative null.
  result <- global_moran(grid, "equipment_n", queen = FALSE, nsim = 19L, seed = 11L)
  expect_equal(result$n_cells, 4L)
  expect_equal(result$moran_i, 0)
  expect_gt(result$permutation_sd, 0)
  expect_length(result$permutation_values, 19L)
  expect_gte(result$pseudo_p, 0)
  expect_lte(result$pseudo_p, 1)
  expect_identical(.Random.seed, original_seed)
})

test_that("seed controls permutations while preserving the observed Moran and caller RNG", {
  skip_if_not_installed("spdep")
  withr::local_seed(1234)
  original_seed <- .Random.seed
  grid <- areal_fixture()
  first <- global_moran(grid, "equipment_n", nsim = 19L, seed = 11L)
  expect_identical(.Random.seed, original_seed)
  second <- global_moran(grid, "equipment_n", nsim = 19L, seed = 11L)
  expect_identical(first$permutation_values, second$permutation_values)
  expect_identical(first$test, second$test)
  other <- global_moran(grid, "equipment_n", nsim = 19L, seed = 12L)
  expect_identical(first$moran_i, other$moran_i)
  expect_false(identical(first$permutation_values, other$permutation_values))
  expect_identical(.Random.seed, original_seed)
  expect_error(global_moran(grid[1:4, ], "equipment_n", nsim = 25L, seed = 11L), "nsim")
  expect_identical(.Random.seed, original_seed)
})

test_that("a local seed does not leave a random stream when none existed", {
  skip_if_not_installed("spdep")
  withr::local_preserve_seed()
  if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
  global_moran(areal_fixture(), "equipment_n", nsim = 19L, seed = 11L)
  expect_false(exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
})

test_that("counts and density are chosen explicitly without automatic conversion", {
  skip_if_not_installed("spdep")
  grid <- areal_fixture()
  counts <- global_moran(grid, "equipment_n", nsim = 19L)
  density <- global_moran(grid, "density_km2", nsim = 19L)
  expect_identical(counts$value_col, "equipment_n")
  expect_identical(density$value_col, "density_km2")
  expect_equal(counts$moran_i, density$moran_i)
  expect_equal(density$n_zero, 1L)
  rook <- global_moran(grid, "equipment_n", queen = FALSE, nsim = 19L)
  expect_identical(rook$neighbour_rule, "rook")
  expect_equal(spdep::card(rook$listw$neighbours)[5], 4L)
  expect_equal(rook$moran_i, 9 / 24 * 80 / 60)
  row_weights <- global_moran(grid, "equipment_n", style = "W", nsim = 19L)
  expect_identical(row_weights$style, "W")
  expect_true(all(vapply(row_weights$listw$weights, sum, numeric(1)) == 1))
  for (alternative in c("greater", "less")) {
    result <- global_moran(grid, "equipment_n", alternative = alternative, nsim = 19L)
    expect_identical(result$alternative, alternative)
    expect_identical(result$test$alternative, alternative)
    expect_gte(result$pseudo_p, 0)
    expect_lte(result$pseudo_p, 1)
  }
})

test_that("islands retain their values and count in the full-cell normalisation", {
  skip_if_not_installed("spdep")
  grid <- areal_fixture()
  sf::st_geometry(grid)[9] <- sf::st_geometry(grid)[9] + c(20, 20)
  original <- grid
  result <- suppressWarnings(global_moran(grid, "equipment_n", nsim = 19L))
  expect_identical(grid, original)
  expect_equal(result$n_cells, 9L)
  expect_equal(result$n_islands, 1L)
  expect_equal(result$n_zero, 1L)
  expect_identical(result$zero.policy, TRUE)
  expect_identical(result$adjust.n, FALSE)
  expect_length(result$listw$neighbours, 9L)
  expect_equal(spdep::card(result$listw$neighbours)[9], 0L)
  expect_equal(spdep::Szero(result$listw), 34)
  expect_equal(result$moran_i, 9 / 34 * 48 / 60)
  expect_true(all(is.finite(result$permutation_values)))
})

test_that("an empty graph and invalid settings fail explicitly", {
  skip_if_not_installed("spdep")
  grid <- areal_fixture()
  isolated <- grid
  for (i in 1:9) sf::st_geometry(isolated)[i] <- sf::st_geometry(isolated)[i] + c(i * 10, 0)
  expect_error(suppressWarnings(global_moran(isolated, "equipment_n", nsim = 19L)), "Nao ha ligacoes")
  expect_error(global_moran(grid, "equipment_n", queen = NA), "queen")
  expect_error(global_moran(grid, "equipment_n", style = "inverse_distance"))
  expect_error(global_moran(grid, "equipment_n", alternative = "automatic"))
  for (seed in list(NULL, NA, NaN, Inf, 1.5, c(1, 2))) {
    expect_error(global_moran(grid, "equipment_n", seed = seed), "seed")
  }
  for (nsim in c(0, -1, NA, Inf, 1.5)) expect_error(global_moran(grid, "equipment_n", nsim = nsim), "nsim")
  grid$hex_id[2] <- grid$hex_id[1]
  expect_error(global_moran(grid, "equipment_n", nsim = 19L), "Identificadores")
})

test_that("hex aggregation conserves points including outer borders and keeps zero cells", {
  fixture <- fixed_domain_fixture()
  grid <- create_hex_grid(fixture$equipment, 1000, fixture$boundary)
  expect_true(all(c("hex_id", "equipment_n", "area_km2", "density_km2") %in% names(grid)))
  expect_equal(sum(grid$equipment_n), nrow(fixture$equipment))
  expect_gt(sum(grid$equipment_n == 0), 0L)
  expect_true(all(grid$area_km2 > 0))
  expect_gt(length(unique(round(grid$area_km2, 6))), 1L)
  expect_equal(sum(grid$area_km2), 6.5 * 5.5, tolerance = 1e-7)
  expect_equal(grid$density_km2, grid$equipment_n / grid$area_km2)
  expect_false(anyDuplicated(grid$hex_id) > 0L)
  empty <- create_hex_grid(fixture$equipment[0, ], 1000, fixture$boundary)
  expect_identical(empty$hex_id, grid$hex_id)
  expect_equal(sf::st_geometry(empty), sf::st_geometry(grid))
  expect_true(all(empty$equipment_n == 0L))
  expect_true(all(empty$density_km2 == 0))
  expect_identical(empty$area_km2, grid$area_km2)
})

test_that("fixed boundary supports two grid scales and observed Moran without models", {
  skip_if_not_installed("spdep")
  local_mocked_bindings(fit_spatial_count_model = function(...) stop("Models forbidden"),
    .package = "sampamaisrural")
  fixture <- fixed_domain_fixture()
  grids <- lapply(c(1000, 2000), function(size) create_hex_grid(fixture$equipment, size, fixture$boundary))
  expect_gt(nrow(grids[[1]]), nrow(grids[[2]]))
  for (grid in grids) {
    expect_equal(sum(grid$equipment_n), nrow(fixture$equipment))
    expect_equal(sum(grid$area_km2), 6.5 * 5.5, tolerance = 1e-7)
    expect_gt(sum(grid$equipment_n == 0), 0L)
    result <- global_moran(grid, "equipment_n", nsim = 19L, seed = 11L)
    expect_equal(result$n_cells, nrow(grid))
    expect_equal(result$n_zero, sum(grid$equipment_n == 0))
    expect_true(is.finite(result$moran_i))
    expect_gte(result$pseudo_p, 0)
    expect_lte(result$pseudo_p, 1)
  }
})
