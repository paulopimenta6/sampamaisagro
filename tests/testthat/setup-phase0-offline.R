# Setup runs after package loading and after testthat's teardown environment exists.
if (identical(Sys.getenv("SAMPA_TEST_OFFLINE"), "1")) {
  testthat::local_mocked_bindings(perform_request = function(...) stop("NETWORK FORBIDDEN"),
    .package = "sampamaisrural", .env = testthat::teardown_env())
  testthat::local_mocked_bindings(req_perform = function(...) stop("NETWORK FORBIDDEN"),
    .package = "httr2", .env = testthat::teardown_env())
}
