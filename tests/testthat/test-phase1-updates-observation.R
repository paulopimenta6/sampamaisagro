# B1a: synthetic fixtures only. The executor never opens a socket.
b1a_bytes <- function(name = "report.json") {
  path <- phase1_path(name)
  readBin(path, "raw", n = file.info(path)$size)
}
b1a_response <- function(status = 200L, headers = list(), body = b1a_bytes()) {
  force(status); force(headers); force(body)
  function(req) httr2::response(status, req$url, method = req$method, headers = headers, body = body)
}
b1a_fake <- function(responses) {
  e <- new.env(parent = emptyenv()); e$requests <- list(); e$sleeps <- numeric()
  e$execute <- function(req, ...) {
    e$requests[[length(e$requests) + 1L]] <- req
    if (length(e$requests) > length(responses)) stop("Unexpected synthetic B1a request")
    responses[[length(e$requests)]](req)
  }
  e$sleep <- function(seconds) { e$sleeps <- c(e$sleeps, seconds) }
  e
}
b1a_run <- function(cfg, fake, identity = phase1_check_identity(), allow_download = TRUE,
                    joint_acceptance_required = FALSE, ...) {
  source_observation_representation(cfg, identity, phase1_registry(), allow_download = allow_download,
    joint_acceptance_required = joint_acceptance_required, execute = fake$execute,
    clock = function() "2030-01-03T00:00:00Z", sleep = fake$sleep, ...)
}
b1a_state <- function(cfg, identity = phase1_check_identity(), bytes = b1a_bytes(), etag = '"old"',
                      modified = NULL, method = "GET") {
  content <- store_source_content(cfg, identity$descriptor$source_id, identity$descriptor$representation, bytes)$content
  state <- source_state_candidate(new_source_state(identity), content, clock = phase1_check_clock)
  state <- source_state_promote(state, phase1_check_validation(), phase1_check_clock)
  state$validated_content["etag_raw"] <- list(etag)
  state$validated_content["last_modified_raw"] <- list(modified)
  state$validated_content$conditional_reuse_allowed <- TRUE
  state$validated_content$conditional_reuse_restrictions <- list()
  state$last_http_observation <- list(observed_at = phase1_check_clock(), method = method,
    request_url = identity$descriptor$absolute_request_url, http_status = 200L,
    etag_raw = etag, last_modified_raw = modified)
  phase1_check_commit(cfg, identity, state, type = "content_validated", sha = content$sha256)
}
b1a_conditions <- function(req) {
  headers <- unclass(req$headers)[intersect(names(req$headers), c("If-None-Match", "If-Modified-Since"))]
  if (length(headers)) headers else list()
}
b1a_files <- function(cfg) {
  paths <- list.files(cfg$data_dir, recursive = TRUE, full.names = TRUE, all.files = TRUE)
  stats::setNames(vapply(paths, sha256_file, character(1)), paths)
}
b1a_guard <- function(envir = parent.frame()) {
  forbidden <- c("commit_source_event", "source_state_candidate", "source_state_promote", "source_state_event",
    "collect_sampa_data", "prepare_equipment_data", "validate_source_pair", "reconcile_source_catalog")
  bindings <- stats::setNames(lapply(forbidden, function(name) {
    force(name); function(...) stop(paste("B1a FORBIDDEN", name))
  }), forbidden)
  do.call(testthat::local_mocked_bindings, c(bindings, list(.package = "sampamaisrural", .env = envir)))
  held <- new.env(parent = emptyenv()); held$cache_locks <- 0L
  acquire <- acquire_source_lock
  testthat::local_mocked_bindings(acquire_source_lock = function(...) {
    # Only the frozen transport's existing blob cache can acquire its own lock.
    cache_call <- vapply(sys.calls(), function(x) identical(x[[1]], as.name("store_source_content")), logical(1))
    if (!any(cache_call)) stop("B1a persistence lock attempted")
    held$cache_locks <- held$cache_locks + 1L
    acquire(...)
  }, .package = "sampamaisrural", .env = envir)
  held
}
b1a_failure <- function(kind, wrapped = TRUE) {
  cause <- structure(list(message = "SYNTHETIC identical opaque text", call = NULL),
    class = c(kind, "curl_error", "error", "condition"))
  if (wrapped) cause <- structure(list(message = "SYNTHETIC wrapper", parent = cause),
    class = c("httr2_failure", "error", "condition"))
  force(cause)
  function(req) stop(cause)
}

test_that("B1a absent state and accepted bytes classify without state persistence", {
  v02_forbid_http(); cfg <- phase1_check_config(); guard <- b1a_guard()
  fake <- b1a_fake(list(b1a_response(headers = list(ETag = '"new"'))))
  out <- b1a_run(cfg, fake)
  expect_identical(out$status, "initialized"); expect_identical(out$content_changed, NA)
  expect_null(out$baseline); expect_null(out$persistence)
  expect_identical(out$planned_event_type, "content_validated")
  expect_identical(out$content$retrieved_at, "2030-01-03T00:00:00Z")
  expect_identical(out$candidate$sha256, digest::digest(b1a_bytes(), algo = "sha256", serialize = FALSE))
  expect_identical(out$validation$decision, "allow")
  expect_silent(source_validation_metadata(out$validation, accepted = TRUE))
  expect_identical(out$context$registry_revision, "synthetic-1")
  expect_null(read_source_state(cfg, phase1_check_identity()))
  expect_identical(guard$cache_locks, 1L)
  paths <- names(b1a_files(cfg))
  expect_length(paths, 1L); expect_match(paths, "/content/demo.base/json/[a-f0-9]{64}\\.bin$")
  expect_false(any(grepl("revisions|current.json|snapshot|processed|manifest", paths)))
  expect_false(dir.exists(file.path(source_operational_root(cfg), "locks/demo.base.lock")))
  expect_false(any(c("body", "payload", "rows", "contacts") %in% names(out)))
  expect_false(grepl("Perfil sintético", paste(capture.output(str(out)), collapse = " "), fixed = TRUE))
})

test_that("B1a compares only the exact accepted identity and preserves history", {
  v02_forbid_http()
  for (same in c(TRUE, FALSE)) {
    cfg <- phase1_check_config(); old <- b1a_state(cfg); before <- b1a_files(cfg)
    fake <- b1a_fake(list(b1a_response(headers = list(ETag = '"new"'),
      body = if (same) b1a_bytes() else b1a_bytes("additive.json"))))
    local({
      b1a_guard()
      out <- b1a_run(cfg, fake)
      expect_identical(out$status, if (same) "content_unchanged" else "content_changed")
      expect_identical(out$content_changed, !same); expect_true(out$metadata_changed)
      expect_identical(out$baseline$sha256, old$validated_content$sha256)
      expect_identical(b1a_conditions(fake$requests[[1]]), list(`If-None-Match` = '"old"'))
      expect_identical(out$planned_event_type, "content_validated"); expect_null(out$persistence)
      expect_identical(source_canonical_json(read_source_state(cfg, old$request_identity)), source_canonical_json(old))
      expect_identical(b1a_files(cfg)[names(before)], before)
    })
  }
  cfg <- phase1_check_config(); a <- phase1_check_identity(); b <- phase1_check_identity(query = "?other=1")
  b1a_state(cfg, a)
  b1a_guard()
  fake <- b1a_fake(list(b1a_response()))
  out <- b1a_run(cfg, fake, b)
  expect_identical(out$status, "initialized"); expect_null(out$baseline)
  expect_identical(out$content_changed, NA); expect_identical(out$metadata_changed, NA)
  expect_length(b1a_conditions(fake$requests[[1]]), 0L)
  fake <- b1a_fake(list(b1a_response()))
  out <- b1a_run(cfg, fake, b, state_lookup = function(...) new_source_state(a))
  expect_identical(out$status, "blocked"); expect_length(fake$requests, 0L)
})

test_that("B1a HEAD compares temporal validators conservatively and never downloads", {
  v02_forbid_http()
  for (headers in list(list(ETag = '"old"'), list(ETag = '"new"'), list(),
      list(ETag = "invalid"), list(ETag = '"old"', `Last-Modified` = "Tue, 01 Jan 2030 00:00:00 GMT"))) {
    cfg <- phase1_check_config(); b1a_state(cfg, method = "HEAD"); before <- b1a_files(cfg)
    local({
      guard <- b1a_guard(); fake <- b1a_fake(list(b1a_response(headers = headers)))
      out <- b1a_run(cfg, fake, allow_download = FALSE)
      expected <- if (identical(headers, list(ETag = '"old"'))) FALSE else
        if (identical(headers, list(ETag = '"new"'))) TRUE else NA
      expect_identical(out$status, if (isTRUE(expected)) "metadata_changed" else "indeterminate")
      expect_identical(out$metadata_changed, expected); expect_identical(out$content_changed, NA)
      expect_identical(fake$requests[[1]]$method, "HEAD"); expect_length(fake$requests, 1L)
      expect_length(b1a_conditions(fake$requests[[1]]), 0L)
      expect_null(out$content); expect_null(out$persistence)
      expect_identical(out$planned_event_type, "check_finished")
      expect_identical(b1a_files(cfg), before); expect_identical(guard$cache_locks, 0L)
    })
  }
  cfg <- phase1_check_config(); b1a_state(cfg, method = "GET")
  fake <- b1a_fake(list(b1a_response(headers = list(ETag = '"new"'))))
  expect_identical(b1a_run(cfg, fake, allow_download = FALSE)$metadata_changed, NA)
  for (status in c(405L, 501L)) {
    fake <- b1a_fake(list(b1a_response(status)))
    out <- b1a_run(cfg, fake, allow_download = FALSE)
    expect_identical(out$status, "source_unavailable"); expect_length(fake$requests, 1L)
    expect_identical(fake$requests[[1]]$method, "HEAD")
  }
  fake <- b1a_fake(list())
  expect_error(b1a_run(cfg, fake, allow_download = FALSE, force_content = TRUE),
    "invalid_download_contract", class = "source_update_argument_error")
  expect_length(fake$requests, 0L)
})

test_that("B1a 304 revalidates current contract, preserves retrieval time and never promotes", {
  v02_forbid_http(); cfg <- phase1_check_config(); old <- b1a_state(cfg); before <- b1a_files(cfg)
  guard <- b1a_guard(); validations <- 0L
  validate <- function(...) { validations <<- validations + 1L; validate_source_payload(...) }
  fake <- b1a_fake(list(b1a_response(304L)))
  out <- b1a_run(cfg, fake, validator = validate)
  expect_identical(out$status, "not_modified"); expect_identical(out$content_changed, NA)
  expect_identical(validations, 1L); expect_null(out$candidate)
  expect_identical(out$content$sha256, old$validated_content$sha256)
  expect_identical(out$content$retrieved_at, old$validated_content$retrieved_at)
  expect_null(out$transport$retrieved_at)
  expect_identical(out$planned_event_type, "content_validated")
  expect_identical(out$validation$contract_id, "sampa.reports")
  strict <- phase1_contract(); strict$version <- 2L; strict$schema$properties$partners$min_items <- 100L
  fake <- b1a_fake(list(b1a_response(304L)))
  out <- b1a_run(cfg, fake, contract_loader = function(...) strict)
  expect_identical(out$status, "incompatible_content"); expect_identical(out$content_changed, NA)
  expect_identical(out$planned_event_type, "state_validation_failed")
  expect_identical(out$validation$contract_version, 2L)
  expect_identical(out$content$retrieved_at, old$validated_content$retrieved_at)
  expect_null(out$persistence); expect_null(out$candidate)
  expect_identical(b1a_files(cfg), before); expect_identical(guard$cache_locks, 0L)
  expect_identical(source_canonical_json(read_source_state(cfg, old$request_identity)), source_canonical_json(old))
})

test_that("B1a delegates cache loss, conditional recovery and force_content to transport", {
  v02_forbid_http()
  for (when in c("before", "after_304")) {
    cfg <- phase1_check_config(); old <- b1a_state(cfg)
    path <- source_safe_path(source_operational_root(cfg), old$validated_content$relative_path)
    revision <- phase1_check_revision(cfg, old$request_identity); before <- sha256_file(revision)
    if (when == "before") unlink(path) # Only a synthetic fixture blob.
    first <- function(req) { unlink(path); b1a_response(304L)(req) }
    responses <- c(if (when == "after_304") list(first), list(b1a_response(body = b1a_bytes("additive.json"))))
    fake <- b1a_fake(responses)
    local({
      b1a_guard(); out <- b1a_run(cfg, fake)
      expect_identical(out$status, "content_changed"); expect_true(out$content_changed)
      expect_identical(out$transport$recovery, when == "after_304")
      expect_identical(out$transport$http_status, 200L)
      expect_identical(out$content$retrieved_at, "2030-01-03T00:00:00Z")
      expect_length(b1a_conditions(tail(fake$requests, 1)[[1]]), 0L)
      expect_identical(sha256_file(revision), before); expect_length(fake$sleeps, 0L)
    })
  }
  cfg <- phase1_check_config(); b1a_state(cfg)
  fake <- b1a_fake(list(b1a_response()))
  out <- b1a_run(cfg, fake, force_content = TRUE)
  expect_identical(out$status, "content_unchanged"); expect_length(b1a_conditions(fake$requests[[1]]), 0L)
  cfg <- phase1_check_config(); old <- b1a_state(cfg, etag = NULL, modified = "Tue, 01 Jan 2030 00:00:00 GMT")
  fake <- b1a_fake(list(b1a_response(304L)))
  expect_identical(b1a_run(cfg, fake)$status, "not_modified")
  expect_identical(b1a_conditions(fake$requests[[1]]), list(`If-Modified-Since` = "Tue, 01 Jan 2030 00:00:00 GMT"))
})

test_that("B1a new incompatible bytes only plan candidate storage", {
  v02_forbid_http()
  for (name in c("missing-required.json", "malformed.json", "type-drift.json")) {
    cfg <- phase1_check_config(); old <- b1a_state(cfg); revision <- phase1_check_revision(cfg, old$request_identity)
    before <- sha256_file(revision)
    local({
      b1a_guard(); fake <- b1a_fake(list(b1a_response(body = b1a_bytes(name))))
      out <- b1a_run(cfg, fake)
      expect_identical(out$status, "incompatible_content"); expect_identical(out$content_changed, NA)
      expect_identical(out$planned_event_type, "candidate_stored"); expect_identical(out$validation$decision, "block")
      expect_null(out$persistence); expect_identical(sha256_file(revision), before)
      expect_identical(source_canonical_json(read_source_state(cfg, old$request_identity)), source_canonical_json(old))
    })
  }
})

test_that("B1a operational failures retain typed TLS evidence and original retries", {
  v02_forbid_http(); b1a_guard()
  for (status in c(404L, 429L, 500L, 503L, 501L)) {
    cfg <- phase1_check_config(); tries <- if (status %in% c(429L, 500L, 503L)) 3L else 1L
    fake <- b1a_fake(rep(list(b1a_response(status)), tries))
    out <- b1a_run(cfg, fake)
    expect_identical(out$status, "source_unavailable"); expect_identical(out$retryable, tries == 3L)
    expect_identical(out$reason_codes, paste0("http_", status)); expect_length(fake$requests, tries)
    expect_identical(out$content_changed, NA); expect_identical(out$planned_event_type, "check_finished")
    expect_null(out$persistence); expect_false(dir.exists(cfg$data_dir))
  }
  for (kind in c("curl_error_peer_failed_verification", "curl_error_ssl_issuer_error",
      "curl_error_operation_timedout", "curl_error_couldnt_connect", "curl_error_unsupported_protocol")) {
    for (wrapped in c(TRUE, FALSE)) {
      cfg <- phase1_check_config(); tls <- kind %in% c("curl_error_peer_failed_verification", "curl_error_ssl_issuer_error")
      retry <- kind %in% c("curl_error_operation_timedout", "curl_error_couldnt_connect")
      fake <- b1a_fake(rep(list(b1a_failure(kind, wrapped)), if (retry) 3L else 1L))
      out <- b1a_run(cfg, fake)
      expect_identical(out$status, if (tls) "check_failed" else "source_unavailable")
      expect_identical(out$retryable, retry); expect_identical(out$content_changed, NA)
      expect_identical(out$transport$attempts, if (retry) 3L else 1L)
      expect_identical(fake$sleeps, if (retry) c(1, 2) else numeric())
      if (tls) expect_identical(out$reason_codes, "tls_trust_failure")
      expect_false(grepl("SYNTHETIC|parent|trace", paste(capture.output(str(out)), collapse = " ")))
      expect_false(dir.exists(cfg$data_dir)); expect_null(out$persistence)
    }
  }
  fake <- b1a_fake(list(b1a_response(304L)))
  out <- b1a_run(phase1_check_config(), fake)
  expect_identical(out$status, "check_failed"); expect_false(out$retryable)
  expect_identical(out$error$code, "unsolicited_304")
})

test_that("B1a old failure evidence never contaminates another successful request", {
  v02_forbid_http(); cfg <- phase1_check_config(); b1a_guard()
  fake <- b1a_fake(list(b1a_failure("curl_error_peer_failed_verification"), b1a_response()))
  failed <- b1a_run(cfg, fake, allow_download = FALSE)
  success <- b1a_run(cfg, fake)
  expect_identical(failed$status, "check_failed"); expect_identical(success$status, "initialized")
  expect_null(success$error); expect_false("tls_trust_failure" %in% success$reason_codes)
  fake <- b1a_fake(list(b1a_failure("curl_error_operation_timedout"), b1a_response()))
  success <- b1a_run(cfg, fake)
  expect_identical(success$status, "initialized"); expect_identical(success$transport$attempts, 2L)
  expect_null(success$error); expect_identical(fake$sleeps, 1)
  bug <- structure(list(message = "synthetic programming defect", call = NULL), class = c("b1a_bug", "error", "condition"))
  for (boundary in c("executor", "reader", "validator", "state_lookup")) {
    fake <- b1a_fake(list(if (boundary == "executor") function(req) stop(bug) else b1a_response()))
    args <- list(cfg = cfg, fake = fake)
    if (boundary != "executor") args[[boundary]] <- function(...) stop(bug)
    expect_identical(tryCatch(do.call(b1a_run, args), b1a_bug = identity), bug)
  }
})

test_that("B1a redirects load target state, isolate validators and keep terminal identity", {
  v02_forbid_http()
  a <- phase1_check_identity(); b <- phase1_check_identity(query = "?hop=B")
  for (own in c(FALSE, TRUE)) {
    cfg <- phase1_check_config(); b1a_state(cfg, a, etag = '"A"')
    if (own) b1a_state(cfg, b, etag = '"B"')
    before <- b1a_files(cfg)
    local({
      b1a_guard()
      fake <- b1a_fake(list(b1a_response(302L, list(Location = "?hop=B")), b1a_response(headers = list(ETag = '"B"'))))
      out <- b1a_run(cfg, fake, a)
      expect_true(out$redirected); expect_identical(out$transport$identity, b)
      expect_identical(out$context$effective_identity, b)
      expect_identical(out$status, if (own) "content_unchanged" else "initialized")
      expect_identical(out$metadata_changed, if (own) FALSE else NA)
      expect_identical(out$transport$http_status, 200L)
      expect_identical(b1a_conditions(fake$requests[[1]]), list(`If-None-Match` = '"A"'))
      expect_identical(b1a_conditions(fake$requests[[2]]), if (own) list(`If-None-Match` = '"B"') else list())
      if (own) expect_identical(out$baseline$identity_sha256, b$sha256) else expect_null(out$baseline)
      expect_identical(b1a_files(cfg), before)
      expect_null(out$persistence)
    })
  }
})

test_that("B1a corrupt state blocks before initial HTTP and at redirect targets", {
  v02_forbid_http(); a <- phase1_check_identity(); b <- phase1_check_identity(query = "?hop=B")
  for (download in c(FALSE, TRUE)) for (destination in c(FALSE, TRUE)) {
    cfg <- phase1_check_config(); id <- if (destination) b else a
    b1a_state(cfg, id); path <- phase1_check_revision(cfg, id)
    writeLines("synthetic corrupt state", path)
    before <- b1a_files(cfg)
    local({
      guard <- b1a_guard()
      fake <- b1a_fake(list(b1a_response(302L, list(Location = "?hop=B")), b1a_response()))
      out <- b1a_run(cfg, fake, a, allow_download = download)
      expect_identical(out$status, "blocked"); expect_identical(out$error$code, "invalid_json")
      expect_length(fake$requests, if (destination) 1L else 0L)
      expect_identical(out$context$effective_identity, id)
      expect_null(out$transport$http_status); expect_null(out$planned_event_type)
      expect_true("transport" %in% names(out))
      expect_null(out$persistence); expect_identical(guard$cache_locks, 0L)
      expect_identical(b1a_files(cfg), before)
      if (destination) {
        expect_true(out$redirected); expect_identical(out$transport$requests[[1]]$status, 302L)
        expect_identical(out$transport$requests[[1]]$identity_sha256, a$sha256)
      }
    })
  }
})

test_that("B1a recovery redirects validate destination state and never reuse conditions", {
  v02_forbid_http(); a <- phase1_check_identity(); b <- phase1_check_identity(query = "?hop=B")
  for (corrupt in c(FALSE, TRUE)) {
    cfg <- phase1_check_config(); old <- b1a_state(cfg, a)
    b1a_state(cfg, b, bytes = b1a_bytes("additive.json"), etag = '"B"')
    if (corrupt) writeLines("synthetic corrupt destination", phase1_check_revision(cfg, b))
    revision <- phase1_check_revision(cfg, b); before <- sha256_file(revision)
    path <- source_safe_path(source_operational_root(cfg), old$validated_content$relative_path)
    first <- function(req) { unlink(path); b1a_response(304L)(req) }
    fake <- b1a_fake(list(first, b1a_response(302L, list(Location = "?hop=B")),
      b1a_response(body = b1a_bytes("additive.json"))))
    local({
      b1a_guard(); out <- b1a_run(cfg, fake)
      expect_identical(out$status, if (corrupt) "blocked" else "content_unchanged")
      expect_true(out$transport$recovery); expect_true(out$redirected)
      expect_identical(out$context$effective_identity, b)
      expect_length(fake$requests, if (corrupt) 2L else 3L)
      expect_true(all(vapply(fake$requests[-1], function(req) length(b1a_conditions(req)) == 0L, logical(1))))
      expect_identical(sha256_file(revision), before); expect_null(out$persistence)
      if (corrupt) expect_null(out$transport$http_status) else expect_identical(out$baseline$identity_sha256, b$sha256)
    })
  }
})

test_that("B1a schema decisions and persisted structural profiles retain 1A semantics", {
  v02_forbid_http(); cfg <- phase1_check_config(); old <- b1a_state(cfg)
  payload <- phase1_json()
  validation <- validate_source_payload(payload, phase1_contract())
  validation$profile <- profile_source_schema(payload)
  old$validated_content$validation <- source_update_validation_metadata(validation, TRUE)
  phase1_check_commit(cfg, old$request_identity, old, 2L, type = "content_validated", sha = old$validated_content$sha256)
  before <- b1a_files(cfg); b1a_guard()
  payload$partners <- lapply(payload$partners, function(row) row[!names(row) %in% "Longitude"])
  changed <- charToRaw(as.character(jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null")))
  fake <- b1a_fake(list(b1a_response(body = changed)))
  out <- b1a_run(cfg, fake)
  expect_identical(out$validation$classification, "suspicious")
  expect_identical(out$validation$decision, "warn")
  expect_identical(out$status, "content_changed")
  expect_true("optional_field_disappeared" %in% vapply(out$validation$evidence$changes, `[[`, character(1), "code"))
  expect_identical(b1a_files(cfg)[names(before)], before)
  fake <- b1a_fake(list(b1a_response(body = charToRaw("synthetic_column\nsynthetic_value\n"))))
  out <- b1a_run(cfg, fake, phase1_check_identity("csv"), joint_acceptance_required = TRUE)
  expect_identical(out$status, "incompatible_content"); expect_identical(out$reason_codes, "csv_required_columns")
  expect_identical(out$planned_event_type, "candidate_stored"); expect_null(out$validation$pair_evidence)
})

test_that("B1a joint context defers acceptance without pairing or state changes", {
  v02_forbid_http(); cfg <- phase1_check_config(); old <- b1a_state(cfg)
  b1a_guard()
  for (fmt in c("json", "csv")) {
    fake <- b1a_fake(list(b1a_response(body = b1a_bytes(paste0("report.", fmt)))))
    out <- b1a_run(cfg, fake, phase1_check_identity(fmt), joint_acceptance_required = NULL)
    expect_identical(out$status, "indeterminate"); expect_identical(out$content_changed, NA)
    expect_true(out$joint_acceptance_required); expect_null(out$planned_event_type)
    expect_null(out$persistence); expect_null(out$validation$pair_evidence)
    expect_true("joint_acceptance_pending" %in% out$reason_codes)
    if (fmt == "json") {
      expect_identical(source_canonical_json(read_source_state(cfg, old$request_identity)), source_canonical_json(old))
    } else expect_null(read_source_state(cfg, phase1_check_identity(fmt)))
    if (fmt == "csv") {
      expect_identical(out$validation$kind, "csv_structure")
      expect_identical(out$validation$evidence$quality, "partial")
      expect_identical(out$validation$classification, "insufficient_evidence")
    }
  }
  fake <- b1a_fake(list(b1a_response(304L, list(ETag = '"new"'))))
  out <- b1a_run(cfg, fake, joint_acceptance_required = TRUE)
  expect_identical(out$status, "metadata_changed"); expect_true(out$metadata_changed)
  expect_identical(out$content_changed, NA); expect_null(out$planned_event_type)
  expect_identical(out$content$retrieved_at, old$validated_content$retrieved_at)
  expect_true("joint_acceptance_pending" %in% out$reason_codes)
  fake <- b1a_fake(list())
  expect_error(b1a_run(cfg, fake, phase1_check_identity("csv")), "invalid_joint_context")
  expect_length(fake$requests, 0L)
})

test_that("B1a helpers neither call persistence nor replace the pure Unit A core", {
  ns <- asNamespace("sampamaisrural")
  symbols <- ls(ns, pattern = "^source_observation_")
  expect_true(length(symbols) > 0L)
  calls <- unique(unlist(lapply(symbols, function(name) all.names(body(get(name, ns))))))
  forbidden <- c("commit_source_event", "source_state_promote", "source_state_candidate", "source_state_event",
    "store_source_content", "acquire_source_lock", "with_source_lock", "collect_sampa_data", "prepare_equipment_data",
    "validate_source_pair", "reconcile_source_catalog", "writeBin", "writeLines", "dir.create", "saveRDS")
  expect_false(any(forbidden %in% calls))
  expect_false(any(symbols %in% getNamespaceExports(ns)))
  expect_false(exists("sampa_check_updates", ns, inherits = FALSE))
  expect_false(exists("source_update_observe_representation", ns, inherits = FALSE))
})
