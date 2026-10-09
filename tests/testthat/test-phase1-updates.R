# Unit A: invented hashes/headers and the existing explicitly synthetic 1A inputs.
update_a_sha <- function(letter = "a") strrep(letter, 64L)
update_a_bytes <- function(letter = "b", identity = update_a_sha()) {
  list(identity_sha256 = identity, sha256 = update_a_sha(letter))
}
update_a_observation <- function(etag = '"synthetic-a"', modified = NULL,
                                 identity = update_a_sha(), method = "HEAD") {
  headers <- list(etag = etag, `last-modified` = modified)
  list(identity_sha256 = identity, method = method,
    headers = headers[!vapply(headers, is.null, logical(1))])
}
update_a_200 <- function(sha = "b", baseline = NULL, ...) {
  source_update_classify_representation("accepted_200", update_a_sha(), update_a_sha(sha), baseline, ...)
}

test_that("1B III A has exactly ten statuses and rejects partial and contradictory results", {
  expected <- c("initialized", "content_unchanged", "content_changed", "not_modified", "metadata_changed",
    "indeterminate", "incompatible_content", "source_unavailable", "check_failed", "blocked")
  expect_identical(source_update_statuses(), expected)
  expect_length(unique(source_update_statuses()), 10L)
  for (bad in list("partial", "candidate", "", NA_character_, c("blocked", "check_failed"), 1L)) {
    expect_error(source_update_result(bad), class = "source_update_argument_error")
  }
  for (status in setdiff(expected, c("content_changed", "content_unchanged"))) {
    expect_error(source_update_result(status, content_changed = TRUE), class = "source_update_argument_error")
    expect_error(source_update_result(status, content_changed = FALSE), class = "source_update_argument_error")
  }
  expect_error(source_update_result("content_changed", content_changed = FALSE), "invalid_result_flags")
  expect_error(source_update_result("content_unchanged", content_changed = NA), "invalid_result_flags")
  expect_error(source_update_result("metadata_changed"), "contradictory_metadata_status")
  expect_error(source_update_result("indeterminate", metadata_changed = TRUE), "contradictory_metadata_status")
  expect_error(source_update_result("content_changed"), "missing_candidate_evidence")
  expect_error(source_update_result("not_modified"), "missing_baseline_evidence")
  expect_error(source_update_result("initialized", candidate = update_a_bytes(), baseline = update_a_bytes()), "initialized_with_baseline")
  expect_error(source_update_result("content_changed", candidate = update_a_bytes(), baseline = update_a_bytes()), "contradictory_content_hashes")
  expect_error(source_update_result("not_modified", candidate = update_a_bytes(), baseline = update_a_bytes()), "unexpected_candidate")
  expect_error(source_update_result("blocked", metadata_changed = 1), "invalid_result_flags")
})

test_that("1B III A classifies accepted bytes only against the same identity", {
  first <- update_a_200()
  expect_identical(first$status, "initialized")
  expect_identical(first$content_changed, NA)
  expect_null(first$baseline)
  expect_identical(first$candidate, update_a_bytes())
  same <- update_a_200(baseline = update_a_bytes())
  expect_identical(same$status, "content_unchanged")
  expect_identical(same$content_changed, FALSE)
  different <- update_a_200("c", update_a_bytes())
  expect_identical(different$status, "content_changed")
  expect_identical(different$content_changed, TRUE)
  cached <- source_update_classify_representation("accepted_304", update_a_sha(), baseline = update_a_bytes())
  expect_identical(cached$status, "not_modified")
  expect_identical(cached$content_changed, NA)
  expect_null(cached$candidate)
  expect_identical(cached$baseline, update_a_bytes())
  for (out in list(first, same, different, cached)) {
    expect_identical(out$severity, "normal")
    expect_false(out$retryable)
  }
  expect_error(update_a_200(baseline = update_a_bytes(identity = update_a_sha("d"))), "different_content_identities")
  expect_error(source_update_classify_representation("accepted_304", update_a_sha()), "missing_304_baseline")
  expect_error(source_update_classify_representation("accepted_200"), "missing_content_identity")
  expect_error(source_update_classify_representation("accepted_200", update_a_sha()), "invalid_content_hash")
  expect_error(source_update_classify_representation("accepted_304", update_a_sha(), update_a_sha("b"), update_a_bytes()), "unexpected_content_hash")
  expect_error(source_update_classify_representation("head", content_sha256 = update_a_sha()), "unexpected_content_hash")
  expect_error(source_update_classify_representation(c("accepted_200", "blocked")), "invalid_observation")
  expect_error(source_update_classify_representation("partial"), "invalid_observation")
  expect_error(source_update_classify_representation("http_304"), "invalid_observation")
  expect_error(update_a_200(baseline = list(sha256 = update_a_sha("b"))), "invalid_evidence_fields")
})

test_that("1B III A metadata compares valid temporal validators conservatively", {
  x <- "Tue, 01 Jan 2030 00:00:00 GMT"
  y <- "Wed, 02 Jan 2030 00:00:00 GMT"
  compare <- source_update_compare_metadata
  a <- update_a_observation()
  expect_identical(compare(a, a), FALSE)
  expect_identical(compare(a, update_a_observation('"synthetic-b"')), TRUE)
  expect_identical(compare(update_a_observation('W/"synthetic-a"'), a), TRUE)
  old <- update_a_observation(NULL, x)
  expect_identical(compare(old, old), FALSE)
  expect_identical(compare(old, update_a_observation(NULL, y)), TRUE)
  both <- update_a_observation(modified = x)
  expect_identical(compare(both, both), FALSE)
  expect_identical(compare(both, update_a_observation(modified = y)), TRUE)
  for (pair in list(list(both, a), list(a, both), list(old, both),
      list(update_a_observation(NULL), update_a_observation(NULL)), list(NULL, a), list(a, NULL),
      list(a, update_a_observation(identity = update_a_sha("d"))), list(a, update_a_observation(method = "GET")),
      list(a, update_a_observation(method = "POST")))) {
    expect_identical(compare(pair[[1]], pair[[2]]), NA)
  }
  for (bad in list("unquoted", '"bad tag"', NA_character_, "", '"bad\nheader"', c('"a"', '"b"'))) {
    expect_identical(compare(a, update_a_observation(bad)), NA)
  }
  for (bad in c("not a date", "Mon, 01 Jan 2030 00:00:00 GMT", "Tue, 31 Feb 2030 00:00:00 GMT")) {
    expect_identical(compare(both, update_a_observation(modified = bad)), NA)
  }
  duplicate <- a; duplicate$headers <- list(ETag = '"a"', etag = '"a"')
  expect_identical(compare(duplicate, duplicate), NA)
  invalid_with_valid <- both; invalid_with_valid$headers$etag <- "invalid"
  expect_identical(compare(invalid_with_valid, both), NA)
  incomplete <- a; incomplete$headers <- NULL
  expect_identical(compare(incomplete, a), NA)
  ambiguous <- a; names(ambiguous$headers) <- NA_character_
  expect_identical(compare(ambiguous, a), NA)
  expect_identical(compare(list(headers = list()), a), NA)
  # Hash/URL/redirect are not accepted substitutes for observed validators.
  expect_error(compare(c(a, list(content_sha256 = update_a_sha())), a), "invalid_evidence_fields")
  expect_error(compare(c(a, list(effective_url = "https://example.invalid/")), a), "invalid_evidence_fields")
  expect_identical(a, update_a_observation())
})

test_that("1B III A HEAD, redirects and byte changes remain orthogonal", {
  for (metadata in list(TRUE, FALSE, NA)) {
    out <- source_update_classify_representation("head", metadata_changed = metadata, redirected = TRUE)
    expect_identical(out$status, if (isTRUE(metadata)) "metadata_changed" else "indeterminate")
    expect_identical(out$content_changed, NA)
    expect_identical(out$metadata_changed, metadata)
    expect_true(out$redirected)
  }
  out <- update_a_200(baseline = update_a_bytes(), metadata_changed = TRUE, redirected = TRUE)
  expect_identical(out$status, "content_unchanged")
  expect_false(out$content_changed)
  expect_true(out$metadata_changed)
  expect_true(out$redirected)
  for (metadata in list(FALSE, NA)) {
    out <- update_a_200(baseline = update_a_bytes(), metadata_changed = metadata, redirected = TRUE)
    expect_identical(out$metadata_changed, metadata)
    expect_false(out$content_changed)
  }
  # The same immutable identity remains the metadata key even if curl's observed
  # URL spelling differed; a genuinely different identity is never normalized.
  id <- phase1_check_identity()
  a <- update_a_observation(identity = id$sha256)
  expect_identical(source_update_compare_metadata(a, a), FALSE)
  b <- a; b$identity_sha256 <- phase1_check_identity(query = "?revision=2")$sha256
  expect_identical(source_update_compare_metadata(a, b), NA)
})

test_that("1B III A known failures carry explicit severity and retryability", {
  cases <- list(
    list("incompatible_content", "schema_breaking", FALSE),
    list("source_unavailable", "http_404", FALSE),
    list("source_unavailable", "transport_timeout", TRUE),
    list("check_failed", "protocol_error", FALSE),
    list("check_failed", "tls_trust_failure", FALSE),
    list("blocked", "state_corrupt", FALSE),
    list("blocked", "lock_busy", TRUE),
    list("blocked", "concurrent_generation", TRUE))
  for (case in cases) {
    out <- source_update_classify_representation(case[[1]], reason_codes = case[[2]], retryable = case[[3]])
    expect_identical(out$status, case[[1]])
    expect_identical(out$content_changed, NA)
    expect_identical(out$severity, "error")
    expect_identical(out$retryable, case[[3]])
    expect_identical(out$reason_codes, case[[2]])
  }
  warn <- source_update_result("indeterminate", reason_codes = "insufficient_evidence", severity = "warning")
  expect_identical(warn$severity, "warning")
  expect_identical(warn$content_changed, NA)
  expect_identical(source_update_result("indeterminate")$severity, "normal")
  expect_error(source_update_result("indeterminate", severity = "warning"), "invalid_severity")
  expect_error(source_update_result("blocked", severity = "normal"), "invalid_severity")
  expect_error(update_a_200(severity = "error"), "invalid_severity")
  expect_error(update_a_200(retryable = TRUE, reason_codes = "timeout"), "invalid_retryability")
  expect_error(source_update_result("check_failed", retryable = TRUE, reason_codes = "tls_trust_failure"), "invalid_retryability")
  expect_error(source_update_result("source_unavailable", retryable = TRUE, reason_codes = "http_404"), "invalid_retryability")
  expect_error(source_update_result("blocked", reason_codes = "OS message with contact@example.invalid"), "invalid_reason_codes")
})

test_that("1B III A result slots carry references and sanitized errors, not payloads", {
  out <- update_a_200()
  expect_identical(out$result_version, 1L)
  expect_null(out$transport)
  expect_null(out$persistence)
  expect_null(out$validation)
  expect_null(out$error)
  expect_false(any(c("body", "payload", "rows", "contacts", "snapshot_should_be_created") %in% names(out)))
  err <- list(kind = "protocol", code = "unsolicited_304")
  expect_identical(source_update_result("check_failed", error = err)$error, err)
  for (bad in list(c(err, list(message = "synthetic secret")), c(err, list(stack = "trace")), simpleError("unexpected"))) {
    expect_error(source_update_result("check_failed", error = bad), "invalid_evidence_fields")
  }
  expect_error(source_update_result("indeterminate", error = err), "invalid_error_evidence")
  expect_error(source_update_result("blocked", candidate = c(update_a_bytes(), list(body = raw(1)))), "invalid_evidence_fields")
  expect_error(source_update_result("blocked", baseline = c(update_a_bytes(), list(rows = list()))), "invalid_evidence_fields")
  expect_error(source_update_result("blocked", error = list(kind = "os", code = "connection details")), "invalid_error_evidence")
  expect_identical(update_a_200(), out)
})

test_that("1B III A adapts actual structural schema results without improving partial evidence", {
  payload <- phase1_json()
  validation <- validate_source_payload(payload, phase1_contract(), "demo.base")
  validation$profile <- profile_source_schema(payload)
  validation$contract_sha256 <- update_a_sha("f")
  validation$kind <- "schema"
  original <- validation
  adapted <- source_update_validation_metadata(validation, accepted = TRUE)
  expect_silent(source_validation_metadata(adapted, accepted = TRUE))
  expect_identical(adapted$decision, "allow")
  expect_identical(adapted$classification, "insufficient_evidence")
  expect_identical(adapted$contract_id, validation$contract_id)
  expect_identical(adapted$contract_version, validation$contract_version)
  expect_identical(adapted$contract_sha256, update_a_sha("f"))
  expect_identical(adapted$kind, "schema")
  expect_identical(adapted$fingerprint$evidence_quality, "partial")
  expect_null(adapted$fingerprint$sha256)
  expect_true("sha256" %in% names(adapted$fingerprint))
  expect_identical(adapted$fingerprint$observed_sha256, validation$fingerprint$observed_sha256)
  expect_identical(adapted$fingerprint$unknown_paths, as.list(validation$fingerprint$unknown_paths))
  expect_null(adapted$fingerprint$canonical)
  expect_identical(adapted$evidence$quality, validation$evidence$quality)
  expect_identical(adapted$evidence$record_count, 3L)
  expect_identical(adapted$evidence$changes, list())
  expect_false(any(c("source_id", "representation", "changes") %in% names(adapted)))
  expect_identical(validation, original)
  expect_identical(source_update_validation_metadata(adapted, accepted = TRUE), adapted)
  expect_identical(source_canonical_json(adapted), source_canonical_json(
    jsonlite::parse_json(source_canonical_json(adapted), simplifyVector = FALSE)))
  # Run each existing schema category through the adapter, including real changes.
  for (name in c("additive.json", "missing-required.json", "type-drift.json", "nested-drift.json", "empty.json")) {
    input <- phase1_validate(name)
    result <- source_update_validation_metadata(input)
    expect_silent(source_validation_metadata(result))
    expect_identical(result$classification, input$classification)
    expect_identical(result$decision, input$decision)
    expect_length(result$evidence$changes, nrow(input$changes))
  }
})

test_that("1B III A structural tables, classes and missing scalars become canonical", {
  changes <- data.frame(path = "$/synthetic", code = "observed_type_change", expected = "string",
    observed = "number", severity = "suspicious", stringsAsFactors = TRUE)
  validation <- structure(list(decision = "warn", classification = "suspicious", changes = changes,
    evidence = list(quality = "partial", record_count = NA_integer_, observed_paths = 1L,
      unknown_paths = c("$/synthetic", NA_character_))), class = "synthetic_validation")
  result <- source_update_validation_metadata(validation)
  expect_silent(source_validation_metadata(result))
  expect_null(result$evidence$record_count)
  expect_true("record_count" %in% names(result$evidence))
  expect_identical(result$evidence$unknown_paths, list("$/synthetic", NULL))
  expect_identical(result$evidence$changes, list(list(path = "$/synthetic", code = "observed_type_change",
    expected = "string", observed = "number", severity = "suspicious")))
  expect_null(attr(result, "class"))
  expect_false(is.data.frame(result$evidence$changes))
  minimal <- source_update_validation_metadata(list(decision = "allow", classification = "valid"))
  expect_identical(names(minimal), c("decision", "classification"))
  for (bad in list(Inf, -Inf, NaN)) {
    validation$evidence$record_count <- bad
    expect_error(source_update_validation_metadata(validation), "nonfinite_structural_value")
  }
  validation <- list(decision = "allow", classification = "valid", evidence = list(record_count = -1L))
  expect_error(source_update_validation_metadata(validation), "invalid_structural_value")
  expect_error(source_update_validation_metadata(list(decision = "block", classification = "breaking"), TRUE), "invalid_content_validation")
  expect_error(source_update_validation_metadata(list(decision = NA_character_, classification = "valid")), "invalid_content_validation")
})

test_that("1B III A preserves structural paths emitted for unusual JSON field names", {
  for (field in c("", "synthetic\nfield", "synthetic/field", "synthetic~field", "synthetic*field")) {
    payload <- phase1_json()
    payload$partners[[1]] <- c(payload$partners[[1]], stats::setNames(list("synthetic value excluded"), field))
    validation <- validate_source_payload(payload, phase1_contract(), "demo.base")
    validation$profile <- profile_source_schema(payload)
    if (nzchar(field)) validation$pair_evidence <- list(comparison = list(compared_fields = field))
    adapted <- source_update_validation_metadata(validation)
    expect_silent(source_validation_metadata(adapted))
    expect_identical(adapted$classification, validation$classification)
    expect_identical(adapted$decision, validation$decision)
    path <- source_path("$/partners/*", field)
    expect_true(path %in% vapply(adapted$profile$nodes, `[[`, character(1), "path"))
    expect_true(path %in% vapply(adapted$evidence$changes, `[[`, character(1), "path"))
    expect_false(grepl("synthetic value excluded", source_canonical_json(adapted), fixed = TRUE))
    if (nzchar(field)) expect_identical(adapted$pair_evidence$comparison$compared_fields, list(field))
  }
})

test_that("1B III A nested whitelists exclude payload, rows, contacts and opaque data", {
  marker <- "SYNTHETIC_PRIVATE_VALUE"
  validation <- phase1_validate()
  validation$payload <- list(marker); validation$rows <- data.frame(contact = marker)
  validation$contacts <- marker
  validation$evidence$rows <- list(marker); validation$evidence$payload <- marker
  validation$profile <- list(profile_version = 1L, rows = marker, nodes = list(list(path = "$/known",
    types = "string", observations = 1L, nulls = 0L, object_observations = 0L, value = marker, contacts = marker)))
  validation$fingerprint$canonical <- paste0('{"payload":"', marker, '"}')
  validation$fingerprint$payload <- marker
  validation$changes <- data.frame(path = "$/known", code = "additional_field", expected = "not declared",
    observed = "additional structural field", severity = "additive", rows = marker, contacts = marker)
  validation$pair_evidence <- list(check_id = "synthetic-check", payload = marker,
    partner = list(representation = "csv", content_sha256 = update_a_sha("e"), rows = marker),
    comparison = list(compared_fields = "synthetic_field", rows = list(marker), contacts = marker))
  adapted <- source_update_validation_metadata(validation)
  expect_silent(source_validation_metadata(adapted))
  expect_false(grepl(marker, source_canonical_json(adapted), fixed = TRUE))
  expect_false(any(c("payload", "rows", "contacts") %in% names(adapted)))
  expect_identical(adapted$pair_evidence$partner, list(representation = "csv", content_sha256 = update_a_sha("e")))
  expect_identical(adapted$pair_evidence$comparison, list(compared_fields = list("synthetic_field")))
  validation$changes$observed <- marker
  expect_error(source_update_validation_metadata(validation), "invalid_structural_value")
  validation$changes$observed <- "additional structural field"
  validation$profile$nodes[[1]]$types <- marker
  expect_error(source_update_validation_metadata(validation), "invalid_structural_value")
  expect_error(source_update_validation_metadata(list(decision = "allow", classification = "valid",
    evidence = list(record_count = list(rows = marker)))), "invalid_structural_value")
})

test_that("1B III A accepts supplied pair evidence without computing or promoting a pair", {
  evidence <- list(check_id = "synthetic-cycle", representation = "json",
    requested_identity_sha256 = update_a_sha(), effective_identity_sha256 = update_a_sha(),
    content_sha256 = update_a_sha("b"), partner = list(representation = "csv",
      requested_identity_sha256 = update_a_sha("c"), effective_identity_sha256 = update_a_sha("d"),
      content_sha256 = update_a_sha("e"), event_id = "synthetic-csv", state_revision = 2L),
    classification = "consistent_under_projection", decision = "allow", contract_id = "synthetic.reports",
    contract_version = 1L, contract_sha256 = update_a_sha("f"), registry_revision = "1.0.0",
    event_id = "synthetic-json", state_revision = 3L,
    comparison = list(json_records = 1L, csv_records = 1L, row_multiset_matches = TRUE, projection_lossy = TRUE,
      comparison_coverage = list(total_fields = 1L, compared_fields = 1L, unsupported_fields = 0L)))
  input <- list(decision = "allow", classification = "valid", pair_evidence = evidence)
  expect_identical(source_update_validation_metadata(input, TRUE)$pair_evidence, evidence)
  expect_silent(source_validation_metadata(source_update_validation_metadata(input, TRUE), TRUE))
  input$pair_evidence$decision <- "block"
  expect_error(source_update_validation_metadata(input, TRUE), "blocked_pair_evidence")
  expect_identical(source_update_validation_metadata(input)$pair_evidence$decision, "block")
})

test_that("1B III A unexpected programming conditions propagate unchanged", {
  bug <- structure(list(message = "synthetic unexpected bug", call = NULL), class = c("synthetic_bug", "error", "condition"))
  testthat::local_mocked_bindings(source_http_validators = function(...) stop(bug), .package = "sampamaisrural")
  out <- tryCatch(source_update_compare_metadata(update_a_observation(), update_a_observation()), synthetic_bug = identity)
  expect_identical(out, bug)
  expect_false(is.list(out) && "status" %in% names(out))
  testthat::local_mocked_bindings(source_validation_metadata = function(...) stop(bug), .package = "sampamaisrural")
  expect_error(source_update_validation_metadata(list(decision = "allow", classification = "valid")), class = "synthetic_bug")
  expect_error(source_update_classify_representation(stop(bug)), class = "synthetic_bug")
})

test_that("1B III A is internal, deterministic and performs no IO or future-unit work", {
  validation <- phase1_validate()
  v02_forbid_http()
  forbidden <- c("source_http_request", "source_http_perform", "read_source_state", "read_source_revisions",
    "commit_source_event", "store_source_content", "source_state_candidate", "source_state_promote",
    "acquire_source_lock", "with_source_lock", "validate_source_pair", "reconcile_source_catalog",
    "load_source_registry", "collect_sampa_data", "prepare_equipment_data", "source_state_now", "source_state_id")
  bindings <- stats::setNames(lapply(forbidden, function(name) {
    force(name); function(...) stop(paste("FORBIDDEN", name))
  }), forbidden)
  do.call(testthat::local_mocked_bindings, c(bindings, list(.package = "sampamaisrural", .env = environment())))
  directory <- withr::local_tempdir()
  withr::local_dir(directory)
  before <- list.files(directory, all.files = TRUE, recursive = TRUE, no.. = TRUE)
  expect_identical(update_a_200(), update_a_200())
  expect_identical(source_update_compare_metadata(update_a_observation(), update_a_observation()), FALSE)
  expect_silent(source_update_validation_metadata(validation))
  expect_identical(source_update_classify_representation("head")$status, "indeterminate")
  expect_identical(source_update_classify_representation("blocked")$status, "blocked")
  expect_identical(list.files(directory, all.files = TRUE, recursive = TRUE, no.. = TRUE), before)
  ns <- asNamespace("sampamaisrural")
  expect_false(any(startsWith(getNamespaceExports(ns), "source_update_")))
  for (name in c("sampa_check_updates", "source_update_observe_representation", "source_update_commit", "source_update_check_source")) {
    expect_false(exists(name, ns, inherits = FALSE))
  }
  # Static call inspection complements dynamic mocks for every helper, including
  # rarely exercised argument guards, without reading source paths at runtime.
  calls <- unique(unlist(lapply(ls(ns, pattern = "^source_update_"), function(name) all.names(body(get(name, ns))))))
  expect_false(any(forbidden %in% calls))
  expect_false(any(c("file", "writeLines", "writeBin", "dir.create", "saveRDS", "Sys.time", "Sys.sleep") %in% calls))
})
