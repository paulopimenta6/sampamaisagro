test_that("origin schema accepts exactly one location method", {
  cfg <- read_sampa_config()
  valid <- validate_origins(data.frame(query_id = "a", latitude = -23.55, longitude = -46.63), cfg)
  expect_equal(nrow(valid$valid), 1)
  invalid <- validate_origins(data.frame(query_id = "a", cep = "01001000", latitude = -23.55, longitude = -46.63), cfg)
  expect_true("multiple_methods" %in% invalid$errors$code)
})

test_that("CEP normalization is strict", {
  checked <- validate_origins(data.frame(query_id = c("a", "b"), cep = c("01001-000", "123")))
  expect_equal(checked$valid$cep, "01001000")
  expect_true(any(checked$errors$query_id == "b"))
})
