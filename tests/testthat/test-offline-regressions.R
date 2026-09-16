test_that("resolved CEPs survive proximity validation without losing provenance", {
  cfg <- read_sampa_config(overrides = list(data_dir = withr::local_tempdir()))
  ensure_project_dirs(cfg)
  cached <- data.frame(cep = "05586001", latitude = -23.571872, longitude = -46.730196,
    geocode_status = "ok", geocoder = "test fixture", geocoded_at = "2026-01-01 UTC")
  attr(cached, "cache_schema") <- 2L
  saveRDS(cached, file.path(cfg$data_dir, "cache", "cep", "05586001.rds"))
  local_mocked_bindings(perform_request = function(...) stop("NETWORK FORBIDDEN"))
  resolved <- resolve_origins(data.frame(cep = "05586-001"), cfg)
  result <- calculate_proximity(resolved$valid, demo_equipment(), config = cfg)
  expect_gt(nrow(result), 0)
  expect_true(all(result$origin_cep == "05586001"))
  expect_true(all(result$geocode_source == "test fixture"))
  expect_error(geocode_cep("01001000", cfg), "índice local")
  expect_error(load_equipment_data(cfg), "Nenhum snapshot")
})

test_that("origin validation handles empty inputs, malformed CEP, and fractional k", {
  expect_equal(nrow(validate_origins(data.frame(cep = character()))$valid), 0)
  expect_equal(nrow(resolve_origins(data.frame(cep = character()))$valid), 0)
  expect_true(is.na(normalize_cep("abc05586001")))
  expect_true("invalid_cep" %in% validate_origins(data.frame(cep = "bad",
    latitude = -23.5, longitude = -46.7))$errors$code)
  expect_true("range" %in% validate_origins(data.frame(cep = "05586001", k = 1.5))$errors$code)
  expect_true(nrow(validate_origins(data.frame(latitude = Inf, longitude = -46.7))$errors) > 0)
})

test_that("batch validates duplicate IDs globally and preserves leading zeros", {
  tmp <- withr::local_tempdir()
  cfg <- read_sampa_config(overrides = list(data_dir = tmp, batch = list(chunk_size = 1)))
  input <- data.frame(query_id = c("dup", "valid", "dup"), latitude = -23.55, longitude = -46.63)
  output <- file.path(tmp, "job")
  run <- process_batch(input, output, demo_equipment(), list(), cfg)
  expect_equal(run$summary$error_rows, 2)
  expect_equal(run$summary$valid_rows, 1)
  expect_equal(sort(run$errors$input_row), c(1L, 3L))
  expect_error(process_batch(input, output, demo_equipment(), list(), cfg,
    parameters = list(k = 5)), "parâmetros mudaram")
  path <- file.path(tmp, "ceps.csv")
  readr::write_csv(data.frame(cep = c("05586001", "01001000")), path)
  expect_identical(read_origin_file(path)$cep, c("05586001", "01001000"))
})

test_that("batch honours per-row radius and k", {
  origin <- data.frame(query_id = c("one", "three"), latitude = -23.55, longitude = -46.63,
    k = c(1, 3), radius_m = 1)
  result <- calculate_proximity(origin, demo_equipment(), modes = character())
  expect_equal(sum(result$origin_id == "one"), 5)
  expect_equal(sum(result$origin_id == "three"), 15)
})

test_that("fastest ranks by time rather than distance", {
  x <- data.frame(equipment_id = c("a", "b"), distance_m = c(100, 200), duration_min = c(5, 1),
    path_objective = "fastest")
  ranked <- rank_distance_rows(x, k = 1, radius_m = 1)
  expect_equal(ranked$equipment_id[ranked$selected], "b")
})

test_that("classification is multitag and missing accessibility is not false", {
  x <- demo_equipment()[1:3, ]
  x$equipment_name <- c("Feira Orgânica CEAGESP", "Dona Hortifruti", "Horta escolar")
  x$accessibility_reported <- c("TRUE", "FALSE", NA)
  x <- classify_equipment(x)
  expect_match(x$groups[1], "feiras_organicas")
  expect_match(x$groups[1], "abastecimento")
  expect_equal(nrow(filter_equipment(x, "hortifruti")), 1)
  expect_equal(x$accessibility, c("Informada: sim", "Informada: não", "Não informada"))
  expect_equal(nrow(classify_equipment(x[0, ])), 0)
})

test_that("overlapping reports do not duplicate the complete baseline", {
  tmp <- withr::local_tempdir()
  cfg <- read_sampa_config(overrides = list(data_dir = tmp))
  row <- list(`Nome do Perfil` = "Horta", Categoria = "Agricultura", Fonte = "Oficial",
    `Endereço comercial` = "Rua A", Latitudade = "-23.55", Longitude = "-46.63")
  base <- file.path(tmp, "base-completa-sampa-rural.json")
  part <- file.path(tmp, "hortas.json")
  jsonlite::write_json(list(partners = list(row, row)), base, auto_unbox = TRUE)
  row$Latitudade <- NULL; row$Longitude <- NULL
  jsonlite::write_json(list(partners = list(row)), part, auto_unbox = TRUE)
  manifest <- data.frame(path = c(base, part), format = "json", dataset = c("base", "hortas"))
  data <- prepare_equipment_data(manifest, cfg)
  expect_equal(nrow(data), 1)
  expect_true(is.finite(data$latitude))
  expect_match(data$source_reports, "hortas.json")
  expect_true(file.exists(file.path(tmp, "processed", "equipment.csv")))
  expect_true(file.exists(file.path(tmp, "processed", "equipment.json")))
})
