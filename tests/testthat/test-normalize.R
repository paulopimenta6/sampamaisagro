test_that("normalizer keeps contacts out of canonical columns", {
  raw <- tempfile(fileext = ".json")
  jsonlite::write_json(list(partners = list(list(
    `Nome do Perfil` = "Horta Teste", Categoria = "Agricultura", Fonte = "Teste",
    `Endereço comercial` = "Rua A", Latitudade = "-23,55", Longitude = "-46,63",
    Email = "pessoa@example.org", Telefone = "0000-0000"
  ))), raw, auto_unbox = TRUE)
  normalized <- normalize_sampa_json(raw, "2026-01-01")
  expect_false(any(c("Email", "Telefone", "email", "phone") %in% names(normalized)))
  expect_equal(normalized$equipment_name, "Horta Teste")
})

test_that("collector requires a real contact as well as authorization", {
  cfg <- read_sampa_config(overrides = list(collection = list(authorized = TRUE),
    user_agent = "sampamaisrural-academic (contato: pesquisa@example.org)"))
  expect_error(collect_sampa_data(cfg), "contato de exemplo")
})
