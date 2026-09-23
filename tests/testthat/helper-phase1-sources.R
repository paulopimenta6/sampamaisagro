phase1_path <- function(name) testthat::test_path("..", "fixtures", "phase1", name)
phase1_json <- function(name = "report.json") read_source_payload(phase1_path(name), "json")
phase1_registry <- function() load_source_registry(phase1_path("registry.yml"))
phase1_contract <- function() load_schema_contract("reports-v1.yml")
phase1_validate <- function(name = "report.json", ...) {
  validate_source_payload(phase1_json(name), phase1_contract(), source_id = "demo.base", ...)
}
