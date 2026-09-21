v02_fixtures <- normalizePath(testthat::test_path("..", "fixtures", "v02"))
source(file.path(v02_fixtures, "load.R"), local = TRUE)

v02_test_config <- function(envir = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = envir)
  v02_config(root, v02_fixtures)
}

v02_forbid_http <- function(envir = parent.frame()) {
  testthat::local_mocked_bindings(perform_request = function(...) stop("NETWORK FORBIDDEN"),
    .package = "sampamaisrural", .env = envir)
  testthat::local_mocked_bindings(req_perform = function(...) stop("NETWORK FORBIDDEN"),
    .package = "httr2", .env = envir)
}
