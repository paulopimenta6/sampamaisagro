# Step II: only synthetic responses; the production socket boundary is never used.
http2_response <- function(status = 200L, headers = list(), body = charToRaw("synthetic bytes")) {
  function(request) list(status = status, headers = headers, body = body, url = request$url)
}
http2_fake <- function(responses) {
  e <- new.env(parent = emptyenv()); e$requests <- list(); e$sleeps <- numeric()
  e$perform <- function(request) {
    e$requests[[length(e$requests) + 1L]] <- request
    if (length(e$requests) > length(responses)) stop("Unexpected synthetic request")
    responses[[length(e$requests)]](request)
  }
  e$sleep <- function(seconds) { e$sleeps <- c(e$sleeps, seconds); invisible(NULL) }
  e
}
http2_run <- function(cfg, fake, identity = phase1_check_identity(), ...) {
  source_http_request(cfg, identity, phase1_registry(), performer = fake$perform,
    sleep = fake$sleep, clock = phase1_check_clock, ...)
}
http2_validated <- function(cfg, identity = phase1_check_identity(), etag = 'W/"synthetic"', modified = NULL,
                            allowed = TRUE, bytes = charToRaw("synthetic accepted")) {
  blob <- store_source_content(cfg, identity$descriptor$source_id, identity$descriptor$representation, bytes)$content
  state <- source_state_candidate(new_source_state(identity), blob, clock = phase1_check_clock)
  state <- source_state_promote(state, phase1_check_validation(), phase1_check_clock)
  state$validated_content["etag_raw"] <- list(etag)
  state$validated_content["last_modified_raw"] <- list(modified)
  state$validated_content$conditional_reuse_allowed <- allowed
  state$validated_content$conditional_reuse_restrictions <- list()
  phase1_check_commit(cfg, identity, state, type = "content_validated", sha = blob$sha256)
}
http2_condition <- function(request) {
  headers <- request$headers[intersect(names(request$headers), c("If-None-Match", "If-Modified-Since"))]
  if (length(headers)) headers else list()
}
http2_files <- function(cfg) list.files(cfg$data_dir, recursive = TRUE, all.files = TRUE)

test_that("1B II HEAD is metadata only, including errors, absent headers and redirects", {
  v02_forbid_http()
  for (status in c(200L, 405L, 501L)) {
    cfg <- phase1_check_config()
    fake <- http2_fake(list(http2_response(status, list(ETag = 'W/"head"', `Last-Modified` = "Tue, 01 Jan 2030 00:00:00 GMT"),
      body = charToRaw("BODY MUST NEVER BECOME CONTENT"))))
    result <- http2_run(cfg, fake)
    expect_identical(result$method, "HEAD")
    expect_length(fake$requests, 1)
    expect_identical(result$http_status, status)
    expect_identical(result$observed_etag_raw, 'W/"head"')
    expect_identical(result$observed_last_modified_raw, "Tue, 01 Jan 2030 00:00:00 GMT")
    expect_null(result$content); expect_null(result$retrieved_at)
    expect_false(dir.exists(cfg$data_dir))
    expect_length(http2_condition(fake$requests[[1]]), 0)
    expect_identical(result$outcome, if (status == 200L) "metadata" else "http_error")
  }
  fake <- http2_fake(list(http2_response(200L)))
  expect_identical(http2_run(phase1_check_config(), fake)$outcome, "metadata")
  expect_length(fake$requests, 1)
  cfg <- phase1_check_config()
  state <- http2_validated(cfg)
  before <- vapply(list.files(cfg$data_dir, recursive = TRUE, full.names = TRUE), sha256_file, character(1))
  fake <- http2_fake(list(http2_response(302L, list(Location = "/new/base-sintetica.json")), http2_response(200L)))
  result <- http2_run(cfg, fake)
  expect_identical(vapply(fake$requests, `[[`, character(1), "method"), c("HEAD", "HEAD"))
  expect_true(all(vapply(fake$requests, function(r) !length(http2_condition(r)), logical(1))))
  expect_null(result$retrieved_at)
  expect_identical(vapply(names(before), sha256_file, character(1)), before)
  expect_identical(source_canonical_json(read_source_state(cfg, state$request_identity)), source_canonical_json(state))
})

test_that("1B II GET stores exact raw candidates without committing or validating state", {
  v02_forbid_http()
  testthat::local_mocked_bindings(commit_source_event = function(...) stop("STATE COMMIT FORBIDDEN"),
    source_state_promote = function(...) stop("PROMOTION FORBIDDEN"),
    collect_sampa_data = function(...) stop("COLLECT FORBIDDEN"), prepare_equipment_data = function(...) stop("PREPARE FORBIDDEN"),
    validate_source_payload = function(...) stop("SCHEMA FORBIDDEN"), validate_source_pair = function(...) stop("PAIR FORBIDDEN"),
    schema_fingerprint = function(...) stop("SCHEMA FORBIDDEN"), compare_schema_to_contract = function(...) stop("SCHEMA FORBIDDEN"),
    .package = "sampamaisrural")
  cfg <- phase1_check_config()
  bytes <- c(as.raw(c(239, 187, 191)), charToRaw('synthetic;"ação"\r\n'), as.raw(c(0, 255)))
  fake <- http2_fake(list(http2_response(body = bytes), http2_response(body = bytes)))
  for (reused in c(FALSE, TRUE)) {
    result <- http2_run(cfg, fake, allow_download = TRUE)
    expect_identical(result$outcome, "candidate")
    expect_identical(result$method, "GET")
    expect_identical(result$cache_reused, reused)
    expect_identical(result$content$sha256, digest::digest(bytes, algo = "sha256", serialize = FALSE))
    expect_equal(result$content$bytes, length(bytes))
    path <- source_safe_path(source_operational_root(cfg), result$content$relative_path)
    expect_identical(readBin(path, "raw", n = length(bytes)), bytes)
    expect_identical(result$retrieved_at, phase1_check_clock())
    expect_false(any(grepl("state/|raw/|processed/|manifest|snapshot", http2_files(cfg))))
    expect_null(read_source_state(cfg, phase1_check_identity()))
  }
  expect_length(http2_files(cfg), 1)
  fake <- http2_fake(list(http2_response(body = raw())))
  expect_equal(http2_run(cfg, fake, allow_download = TRUE)$content$bytes, 0)
  fake <- http2_fake(list(http2_response(body = "decoded text")))
  result <- http2_run(cfg, fake, allow_download = TRUE)
  expect_identical(result$error$code, "body_not_raw")
  expect_identical(result$http_status, 200L)
  expect_length(result$requests, 1)
})

test_that("1B II validators belong only to accepted content in the current identity", {
  v02_forbid_http()
  date <- "Tue, 01 Jan 2030 00:00:00 GMT"
  for (tag in c('"simple"', 'W/"weak"')) {
    cfg <- phase1_check_config(); state <- http2_validated(cfg, etag = tag, modified = date)
    fake <- http2_fake(list(http2_response(304L)))
    before <- http2_files(cfg)
    result <- http2_run(cfg, fake, allow_download = TRUE)
    expect_identical(http2_condition(fake$requests[[1]]), list(`If-None-Match` = tag))
    expect_identical(result$condition, list(name = "If-None-Match", value = tag))
    expect_identical(result$outcome, "not_modified")
    expect_identical(result$reused_content$sha256, state$validated_content$sha256)
    expect_true(is.na(result$content_changed)); expect_null(result$retrieved_at); expect_null(result$content)
    expect_identical(http2_files(cfg), before)
    expect_identical(result$identity$sha256, phase1_check_identity()$sha256)
  }
  cfg <- phase1_check_config(); http2_validated(cfg, etag = NULL, modified = date)
  fake <- http2_fake(list(http2_response(304L)))
  expect_identical(http2_run(cfg, fake, allow_download = TRUE)$outcome, "not_modified")
  expect_identical(http2_condition(fake$requests[[1]]), list(`If-Modified-Since` = date))
  for (kind in c("disabled", "no_validator", "head_only", "candidate_only", "other_identity")) {
    cfg <- phase1_check_config()
    if (kind == "disabled") http2_validated(cfg, allowed = FALSE)
    if (kind == "no_validator") http2_validated(cfg, etag = NULL)
    if (kind == "other_identity") http2_validated(cfg, phase1_check_identity(query = "?other=1"))
    if (kind %in% c("head_only", "candidate_only")) {
      identity <- phase1_check_identity(); state <- new_source_state(identity)
      if (kind == "head_only") state$last_http_observation <- list(method = "HEAD", etag_raw = '"head-only"') else {
        blob <- store_source_content(cfg, "demo.base", "json", charToRaw("synthetic candidate"))$content
        state <- source_state_candidate(state, blob, phase1_check_validation("block"), phase1_check_clock)
      }
      phase1_check_commit(cfg, identity, state)
    }
    fake <- http2_fake(list(http2_response()))
    expect_identical(http2_run(cfg, fake, allow_download = TRUE)$outcome, "candidate", info = kind)
    expect_length(http2_condition(fake$requests[[1]]), 0)
  }
  cfg <- phase1_check_config(); state <- http2_validated(cfg)
  fake <- http2_fake(list(http2_response()))
  result <- http2_run(cfg, fake, phase1_check_identity("csv"), allow_download = TRUE)
  expect_identical(result$outcome, "candidate"); expect_length(http2_condition(fake$requests[[1]]), 0)
  fake <- http2_fake(list(http2_response()))
  result <- http2_run(cfg, fake, allow_download = TRUE, state_lookup = function(...) state)
  expect_true(result$condition_sent)
  fake <- http2_fake(list(http2_response()))
  result <- http2_run(cfg, fake, phase1_check_identity("csv"), allow_download = TRUE, state_lookup = function(...) state)
  expect_identical(result$outcome, "blocked"); expect_identical(result$error$code, "state_identity_mismatch")
  expect_length(fake$requests, 0)
})

test_that("1B II invalid and ambiguous validators cannot be reused or leak headers", {
  v02_forbid_http()
  for (bad in c("", "unquoted", '"one", "two"', 'w/"weak"', '"line\r\ninjected"', '"tab\tvalue"', '"with space"')) {
    fake <- http2_fake(list(http2_response(headers = list(ETag = bad, Authorization = "SECRET", `Set-Cookie` = "SECRET"))))
    result <- http2_run(phase1_check_config(), fake, allow_download = TRUE)
    expect_null(result$observed_etag_raw)
    expect_identical(result$diagnostics[[1]]$code, "invalid_validator")
    expect_false(grepl("SECRET|injected", paste(capture.output(str(result)), collapse = " ")))
  }
  for (headers in list(list(ETag = '"a"', etag = '"b"'), list(`Last-Modified` = "not a date"),
      list(`Last-Modified` = c("one", "two")))) {
    fake <- http2_fake(list(http2_response(headers = headers)))
    result <- http2_run(phase1_check_config(), fake, allow_download = TRUE)
    expect_null(result$observed_etag_raw); expect_null(result$observed_last_modified_raw)
    expect_identical(result$diagnostics[[1]]$code, "invalid_validator")
  }
  cfg <- phase1_check_config(); state <- http2_validated(cfg, etag = '"bad\r\nheader"')
  fake <- http2_fake(list(http2_response()))
  result <- http2_run(cfg, fake, allow_download = TRUE)
  expect_length(http2_condition(fake$requests[[1]]), 0)
  expect_identical(result$diagnostics[[1]]$code, "invalid_validator")
  cfg <- phase1_check_config(); http2_validated(cfg, modified = "Tue, 01 Jan 2030 00:00:00 GMT")
  fake <- http2_fake(list(http2_response()))
  result <- http2_run(cfg, fake, allow_download = TRUE)
  expect_null(result$observed_etag_raw); expect_null(result$observed_last_modified_raw)
})

test_that("1B II invalid cache prevents condition and corrupt revision chains block", {
  v02_forbid_http()
  for (kind in c("missing", "size", "hash")) {
    cfg <- phase1_check_config(); state <- http2_validated(cfg)
    path <- source_safe_path(source_operational_root(cfg), state$validated_content$relative_path)
    if (kind == "missing") unlink(path) else writeBin(charToRaw(if (kind == "hash") "synthetic rejected" else "short"), path)
    fake <- http2_fake(list(http2_response()))
    result <- http2_run(cfg, fake, allow_download = TRUE)
    expect_identical(result$outcome, "candidate")
    expect_length(http2_condition(fake$requests[[1]]), 0)
    expect_match(result$diagnostics[[1]]$code, "^content_(missing|size_mismatch|hash_mismatch)$")
  }
  cfg <- phase1_check_config(); http2_validated(cfg)
  path <- phase1_check_revision(cfg, phase1_check_identity())
  writeLines("synthetic corrupted JSON", path)
  fake <- http2_fake(list(http2_response()))
  result <- http2_run(cfg, fake, allow_download = TRUE)
  expect_identical(result$outcome, "blocked"); expect_identical(result$error$code, "invalid_json")
  expect_length(fake$requests, 0)
  expect_identical(readLines(path), "synthetic corrupted JSON")
})

test_that("1B II unsolicited 304 and force contradictions are classified", {
  v02_forbid_http()
  cfg <- phase1_check_config()
  fake <- http2_fake(list(http2_response(304L)))
  result <- http2_run(cfg, fake, allow_download = TRUE)
  expect_identical(result$error$code, "unsolicited_304"); expect_identical(result$outcome, "protocol_error")
  expect_false(dir.exists(cfg$data_dir))
  http2_validated(cfg)
  fake <- http2_fake(list(http2_response(304L)))
  result <- http2_run(cfg, fake, allow_download = TRUE, force_content = TRUE)
  expect_identical(result$error$code, "unsolicited_304")
  expect_length(http2_condition(fake$requests[[1]]), 0)
  expect_null(result$retrieved_at); expect_true(is.na(result$content_changed))
  fake <- http2_fake(list(http2_response(304L)))
  expect_identical(http2_run(cfg, fake)$error$code, "unsolicited_304")
  expect_error(http2_run(cfg, fake, force_content = TRUE), "invalid_argument", class = "source_http_error")
  expect_error(http2_run(cfg, fake, timeout = Inf), "invalid_argument", class = "source_http_error")
  expect_error(http2_run(cfg, fake, max_attempts = 4), "invalid_argument", class = "source_http_error")
})

test_that("1B II post-request cache loss permits one unconditional recovery only", {
  v02_forbid_http()
  for (kind in c("missing", "corrupt")) for (status in c(200L, 304L, 503L)) {
    cfg <- phase1_check_config(); state <- http2_validated(cfg)
    path <- source_safe_path(source_operational_root(cfg), state$validated_content$relative_path)
    revision <- phase1_check_revision(cfg, state$request_identity); before <- sha256_file(revision)
    first <- function(request) {
      if (kind == "missing") unlink(path) else writeBin(charToRaw("synthetic corrupt"), path)
      http2_response(304L)(request)
    }
    fake <- http2_fake(list(first, http2_response(status)))
    result <- http2_run(cfg, fake, allow_download = TRUE)
    expect_length(fake$requests, 2)
    expect_length(http2_condition(fake$requests[[1]]), 1)
    expect_length(http2_condition(fake$requests[[2]]), 0)
    expect_identical(fake$requests[[1]]$identity, fake$requests[[2]]$identity)
    expect_true(result$recovery)
    expect_identical(sha256_file(revision), before)
    expect_length(fake$sleeps, 0)
    if (status == 200L) {
      expect_identical(result$outcome, "candidate"); expect_identical(result$retrieved_at, phase1_check_clock())
    } else {
      expect_null(result$retrieved_at)
      expect_identical(result$error$code, if (status == 304L) "unsolicited_304" else "http_unavailable")
    }
  }
})

# Recovery fixtures and all corruption below are confined to synthetic temp data.
http2_recovery_fixture <- function(loss = "missing", envir = parent.frame()) {
  cfg <- phase1_check_config(envir)
  a <- phase1_check_identity()
  b <- phase1_check_identity(query = "?hop=B")
  c <- phase1_check_identity(query = "?hop=C")
  state <- http2_validated(cfg, a, etag = '"A"', bytes = charToRaw("synthetic A"))
  path <- source_safe_path(source_operational_root(cfg), state$validated_content$relative_path)
  first <- function(request) {
    if (loss == "missing") unlink(path) else writeBin(charToRaw("corrupted A"), path)
    http2_response(304L)(request)
  }
  list(cfg = cfg, a = a, b = b, c = c, path = path, first = first,
    body = charToRaw("synthetic recovery destination body"))
}
http2_recovery_run <- function(case, responses, state_lookup = source_http_state_lookup) {
  testthat::local_mocked_bindings(commit_source_event = function(...) stop("STATE COMMIT FORBIDDEN"),
    source_state_promote = function(...) stop("PROMOTION FORBIDDEN"), .package = "sampamaisrural")
  fake <- http2_fake(c(list(case$first, http2_response(302L, list(Location = "?hop=B"))), responses))
  lookups <- character()
  result <- http2_run(case$cfg, fake, case$a, allow_download = TRUE,
    state_lookup = function(config, identity) {
      lookups <<- c(lookups, identity$sha256)
      state_lookup(config, identity)
    })
  list(result = result, requests = fake$requests, sleeps = fake$sleeps, lookups = lookups)
}
http2_recovery_files <- function(case) {
  paths <- setdiff(list.files(case$cfg$data_dir, recursive = TRUE, full.names = TRUE), case$path)
  vapply(paths, sha256_file, character(1))
}

test_that("1B II P2 recovery state blocks corrupt redirect destinations before HTTP or storage", {
  v02_forbid_http()
  for (loss in c("missing", "corrupt")) for (corruption in c("json", "checksum", "identity")) {
    case <- http2_recovery_fixture(loss)
    http2_validated(case$cfg, case$b, etag = '"B"', bytes = charToRaw("synthetic B"))
    path <- phase1_check_revision(case$cfg, case$b)
    if (corruption == "json") writeLines("synthetic corrupt revision", path)
    if (corruption == "checksum") phase1_check_rewrite(path, function(record) {
      record$state_after$registry_revision_seen <- "synthetic tampering"; record
    }, resign = FALSE)
    if (corruption == "identity") phase1_check_rewrite(path, function(record) {
      record$state_after$request_identity <- case$c; record
    })
    before <- http2_recovery_files(case)
    run <- http2_recovery_run(case, list(http2_response(body = case$body)))
    expect_identical(run$result$outcome, "blocked", info = paste(loss, corruption))
    expect_identical(run$result$error$code, switch(corruption, json = "invalid_json",
      checksum = "invalid_revision_checksum_chain", identity = "state_identity_mismatch"))
    expect_identical(run$result$error$decision, "block")
    expect_true(run$result$recovery)
    expect_identical(run$lookups, c(case$a$sha256, case$a$sha256, case$b$sha256))
    expect_identical(vapply(run$requests, function(r) r$identity$sha256, character(1)), rep(case$a$sha256, 2))
    expect_identical(http2_condition(run$requests[[1]]), list(`If-None-Match` = '"A"'))
    expect_length(http2_condition(run$requests[[2]]), 0)
    expect_null(run$result$content)
    expect_null(run$result$retrieved_at)
    expect_identical(http2_recovery_files(case), before)
    expect_length(run$sleeps, 0)
  }
})

test_that("1B II P2 recovery state permits absent destinations with unconditional GET", {
  v02_forbid_http()
  case <- http2_recovery_fixture()
  expect_null(read_source_state(case$cfg, case$b))
  revision <- phase1_check_revision(case$cfg, case$a); before <- sha256_file(revision)
  run <- http2_recovery_run(case, list(http2_response(body = case$body)))
  expect_identical(run$lookups, c(case$a$sha256, case$a$sha256, case$b$sha256))
  expect_identical(run$result$outcome, "candidate")
  expect_true(run$result$recovery)
  expect_identical(run$result$requested_identity, case$a)
  expect_identical(run$result$identity, case$b)
  expect_identical(vapply(run$requests, `[[`, character(1), "method"), rep("GET", 3))
  expect_identical(vapply(run$requests[-1], function(r) length(http2_condition(r)), integer(1)), c(0L, 0L))
  path <- source_safe_path(source_operational_root(case$cfg), run$result$content$relative_path)
  expect_identical(readBin(path, "raw", n = length(case$body)), case$body)
  expect_identical(sha256_file(revision), before)
  expect_null(read_source_state(case$cfg, case$b))
  expect_length(run$sleeps, 0)
})

test_that("1B II P2 recovery state validates every hop without reusing its validators", {
  v02_forbid_http()
  for (status in c(200L, 304L, 503L)) {
    case <- http2_recovery_fixture()
    http2_validated(case$cfg, case$b, etag = '"B"', bytes = charToRaw("synthetic B"))
    # Also exercise a destination whose own eligible validator is Last-Modified.
    http2_validated(case$cfg, case$c, etag = NULL, modified = "Tue, 01 Jan 2030 00:00:00 GMT",
      bytes = charToRaw("synthetic C"))
    before <- http2_recovery_files(case)
    run <- http2_recovery_run(case, list(http2_response(307L, list(Location = "?hop=C")),
      http2_response(status, body = case$body)))
    expect_identical(run$lookups, c(case$a$sha256, case$a$sha256, case$b$sha256, case$c$sha256))
    expect_identical(vapply(run$requests, function(r) r$identity$sha256, character(1)), run$lookups)
    expect_identical(vapply(run$requests[-1], function(r) length(http2_condition(r)), integer(1)), rep(0L, 3))
    expect_identical(vapply(run$requests, `[[`, character(1), "method"), rep("GET", 4))
    expect_identical(vapply(run$result$requests, `[[`, logical(1), "recovery"), c(FALSE, TRUE, TRUE, TRUE))
    expect_identical(run$result$requested_identity, case$a)
    expect_identical(run$result$identity, case$c)
    expect_identical(run$result$attempts, 4L)
    expect_length(run$sleeps, 0)
    expect_identical(vapply(names(before), sha256_file, character(1)), before)
    if (status == 200L) {
      expect_identical(run$result$outcome, "candidate")
      expect_identical(run$result$content$sha256, digest::digest(case$body, algo = "sha256", serialize = FALSE))
    } else {
      expect_identical(run$result$outcome, if (status == 304L) "protocol_error" else "http_error")
      expect_identical(run$result$error$code, if (status == 304L) "unsolicited_304" else "http_unavailable")
      expect_null(run$result$content)
      expect_identical(http2_recovery_files(case), before)
    }
  }
})

test_that("1B II P2 recovery state blocks corrupt C after valid B without state writes", {
  v02_forbid_http()
  case <- http2_recovery_fixture()
  http2_validated(case$cfg, case$b, etag = '"B"', bytes = charToRaw("synthetic B"))
  state <- http2_validated(case$cfg, case$c, etag = '"C"', bytes = charToRaw("synthetic C"))
  # Corrupt an earlier revision, leaving the latest revision intact.
  phase1_check_commit(case$cfg, case$c, state, number = 2L)
  path <- phase1_check_revision(case$cfg, case$c)
  phase1_check_rewrite(path, function(record) {
    record$state_after$registry_revision_seen <- "synthetic tampering"; record
  }, resign = FALSE)
  before <- http2_recovery_files(case)
  run <- http2_recovery_run(case, list(http2_response(302L, list(Location = "?hop=C")),
    http2_response(body = case$body)))
  expect_identical(run$result$outcome, "blocked")
  expect_identical(run$result$error$code, "invalid_revision_checksum_chain")
  expect_identical(run$lookups, c(case$a$sha256, case$a$sha256, case$b$sha256, case$c$sha256))
  expect_identical(vapply(run$requests, function(r) r$identity$sha256, character(1)),
    c(case$a$sha256, case$a$sha256, case$b$sha256))
  expect_identical(vapply(run$requests[-1], function(r) length(http2_condition(r)), integer(1)), c(0L, 0L))
  expect_identical(run$result$identity, case$c)
  expect_null(run$result$content)
  expect_null(run$result$retrieved_at)
  expect_identical(http2_recovery_files(case), before)
  expect_length(run$sleeps, 0)
})

test_that("1B II P2 recovery state validates identities returned by injected lookups", {
  v02_forbid_http()
  case <- http2_recovery_fixture()
  before <- http2_recovery_files(case)
  run <- http2_recovery_run(case, list(http2_response(body = case$body)),
    state_lookup = function(config, identity) {
      if (identical(identity, case$b)) new_source_state(case$c) else source_http_state_lookup(config, identity)
    })
  expect_identical(run$result$outcome, "blocked")
  expect_identical(run$result$error$code, "state_identity_mismatch")
  expect_identical(run$lookups, c(case$a$sha256, case$a$sha256, case$b$sha256))
  expect_length(run$requests, 2)
  expect_null(run$result$content)
  expect_identical(http2_recovery_files(case), before)
})

test_that("1B II redirects resolve safely and never forward another identity's validator", {
  v02_forbid_http()
  for (own in c(FALSE, TRUE)) {
    cfg <- phase1_check_config(); http2_validated(cfg, etag = '"A"')
    b <- source_request_identity("demo.base", "json", "https://example.invalid/reports/new/base-sintetica.json", phase1_registry())
    if (own) http2_validated(cfg, b, etag = '"B"')
    fake <- http2_fake(list(http2_response(302L, list(Location = "new/base-sintetica.json", ETag = '"redirect"')),
      http2_response(if (own) 304L else 200L)))
    result <- http2_run(cfg, fake, allow_download = TRUE)
    expect_identical(http2_condition(fake$requests[[1]]), list(`If-None-Match` = '"A"'))
    expect_identical(http2_condition(fake$requests[[2]]), if (own) list(`If-None-Match` = '"B"') else list())
    expect_identical(result$identity, b)
    expect_identical(result$effective_url, b$descriptor$absolute_request_url)
    expect_length(result$redirects, 1)
    expect_identical(result$outcome, if (own) "not_modified" else "candidate")
  }
  for (location in c("https://example.invalid/new/base-sintetica.json", "/new/base-sintetica.json",
      "//example.invalid/new/base-sintetica.json", "?synthetic=2")) {
    fake <- http2_fake(list(http2_response(307L, list(Location = location)), http2_response()))
    result <- http2_run(phase1_check_config(), fake, allow_download = TRUE)
    expect_identical(result$outcome, "candidate"); expect_length(result$redirects, 1)
  }
  bad <- c("https://other.invalid/base-sintetica.json", "http://example.invalid/base-sintetica.json",
    "ftp://example.invalid/base-sintetica.json", "https://user:secret@example.invalid/base-sintetica.json",
    "/other-slug.json", "/base-sintetica.csv", "/x/../base-sintetica.json", "../base-sintetica.json",
    "/%2e/base-sintetica.json", "https://example.invalid:8443/base-sintetica.json", "#fragment", "")
  for (location in bad) {
    fake <- http2_fake(list(http2_response(302L, list(Location = location))))
    result <- http2_run(phase1_check_config(), fake, allow_download = TRUE)
    expect_identical(result$error$code, "invalid_redirect", info = location)
    expect_length(fake$requests, 1)
  }
  cfg <- phase1_check_config()
  responses <- lapply(1:5, function(i) http2_response(302L, list(Location = paste0("/v", i, "/base-sintetica.json"))))
  fake <- http2_fake(c(responses, list(http2_response())))
  expect_identical(http2_run(cfg, fake, allow_download = TRUE)$outcome, "candidate")
  expect_length(fake$requests, 6)
  for (loop in c(FALSE, TRUE)) {
    fake <- http2_fake(if (loop) rep(list(http2_response(302L, list(Location = "/reports/base-sintetica.json"))), 6) else
      c(responses, list(http2_response(302L, list(Location = "/six/base-sintetica.json")))))
    result <- http2_run(cfg, fake, allow_download = TRUE)
    expect_identical(result$error$code, "redirect_limit"); expect_length(fake$requests, 6)
    expect_length(result$redirects, 5)
  }
})

test_that("1B II retries and Retry-After are bounded with injected clock and sleep", {
  v02_forbid_http()
  for (status in c(400L, 404L, 401L, 501L)) {
    fake <- http2_fake(list(http2_response(status)))
    expect_identical(http2_run(phase1_check_config(), fake, allow_download = TRUE)$error$kind, "http")
    expect_length(fake$requests, 1); expect_length(fake$sleeps, 0)
  }
  for (status in c(429L, 500L, 502L, 503L, 504L)) {
    fake <- http2_fake(rep(list(http2_response(status)), 3))
    result <- http2_run(phase1_check_config(), fake, allow_download = TRUE)
    expect_identical(result$http_status, status); expect_identical(result$attempts, 3L)
    expect_identical(fake$sleeps, c(1, 2))
    expect_identical(vapply(fake$requests, `[[`, integer(1), "attempt"), 1:3)
  }
  values <- c("10", "Wed, 02 Jan 2030 03:04:15 GMT", "Tue, 01 Jan 2030 00:00:00 GMT", "invalid", "99999999")
  for (i in seq_along(values)) {
    fake <- http2_fake(list(http2_response(429L, list(`Retry-After` = values[i])), http2_response()))
    expect_identical(http2_run(phase1_check_config(), fake, allow_download = TRUE)$outcome, "candidate")
    expect_equal(fake$sleeps, c(10, 10, 0, 1, 60)[i])
  }
  expect_equal(source_http_retry_delay(list(`Retry-After` = "Thu, 03 Jan 2030 00:00:00 GMT"), 1, phase1_check_clock), 60)
  expect_equal(source_http_retry_delay(list(`Retry-After` = "1", `retry-after` = "2"), 2, phase1_check_clock), 2)
  expect_true(is.na(source_http_date("Mon, 01 Jan 2030 00:00:00 GMT")))
  timeout <- function(request) source_http_transport_error("transport_timeout", TRUE)
  fake <- http2_fake(rep(list(timeout), 3))
  result <- http2_run(phase1_check_config(), fake, allow_download = TRUE)
  expect_identical(result$error$code, "transport_timeout"); expect_identical(result$attempts, 3L)
  expect_null(result$http_status); expect_identical(fake$sleeps, c(1, 2))
  fake <- http2_fake(list(timeout, http2_response()))
  expect_identical(http2_run(phase1_check_config(), fake, allow_download = TRUE)$outcome, "candidate")
  bug <- simpleError("synthetic programming defect")
  fake <- http2_fake(list(function(request) stop(bug)))
  expect_identical(tryCatch(http2_run(phase1_check_config(), fake, allow_download = TRUE), error = identity), bug)
  expect_length(fake$requests, 1); expect_length(fake$sleeps, 0)
  fake <- http2_fake(list(function(request) source_state_block("synthetic_local_block")))
  result <- http2_run(phase1_check_config(), fake, allow_download = TRUE)
  expect_identical(result$error$code, "synthetic_local_block"); expect_identical(result$outcome, "blocked")
  expect_length(fake$requests, 1); expect_length(fake$sleeps, 0)
})

test_that("1B II production adapter is exercised without sockets or private APIs", {
  v02_forbid_http()
  bytes <- c(charToRaw("synthetic\r\n"), as.raw(c(0, 255)))
  for (method in c("HEAD", "GET")) {
    observed <- NULL
    execute <- function(req, verbosity) {
      observed <<- req
      expect_equal(verbosity, 0)
      httr2::response(200, url = req$url, method = method,
        headers = list(ETag = 'W/"synthetic"'), body = bytes)
    }
    request <- list(method = method, url = "https://example.invalid/base-sintetica.json",
      headers = list(Accept = "application/json", `Accept-Encoding` = "identity", `If-None-Match` = 'W/"synthetic"'),
      user_agent = "sampamaisagro/synthetic", timeout = 7)
    result <- source_http_perform(request, execute)
    expect_identical(observed$method, method)
    expect_false(observed$options$followlocation)
    expect_equal(observed$options$maxredirs, 0)
    expect_identical(observed$options$nobody, method == "HEAD")
    expect_false(observed$options$http_content_decoding)
    expect_equal(observed$options$timeout_ms, 7000)
    expect_equal(observed$policies$retry_max_tries, 1)
    expect_identical(observed$headers$`If-None-Match`, 'W/"synthetic"')
    expect_identical(result$body, if (method == "HEAD") raw() else bytes)
  }
  request$method <- "GET"
  expect_identical(source_http_perform(request, function(req, ...) httr2::response(200, req$url, body = raw()))$body, raw())
  for (kind in c("curl_error_operation_timedout", "curl_error_couldnt_connect", "curl_error_peer_failed_verification")) {
    cause <- structure(list(message = "SECRET remote payload", call = NULL), class = c(kind, "curl_error", "error", "condition"))
    wrapper <- structure(list(message = "SECRET wrapper", parent = cause), class = c("httr2_failure", "error", "condition"))
    error <- tryCatch(source_http_perform(request, function(...) stop(wrapper)), error = identity)
    expect_s3_class(error, "source_http_transport_error")
    expect_false(grepl("SECRET", conditionMessage(error)))
    expect_identical(error$retryable, kind != "curl_error_peer_failed_verification")
  }
  bug <- simpleError("synthetic adapter bug")
  expect_identical(tryCatch(source_http_perform(request, function(...) stop(bug)), error = identity), bug)
})

test_that("1B II result keeps only necessary HTTP metadata and no payload or state writes", {
  v02_forbid_http()
  cfg <- phase1_check_config()
  fake <- http2_fake(list(http2_response(headers = list(ETag = '"safe"', Authorization = "SECRET_TOKEN", `Set-Cookie` = "SECRET_COOKIE"),
    body = charToRaw('{"synthetic_contact":"SECRET_CONTACT"}'))))
  result <- http2_run(cfg, fake, allow_download = TRUE)
  text <- paste(capture.output(str(result)), collapse = " ")
  expect_false(grepl("SECRET|synthetic_contact|stack|trace", text))
  expect_identical(result$observed_etag_raw, '"safe"')
  expect_false(any(grepl("state/|revisions|raw/|processed/|manifest|snapshot", http2_files(cfg))))
  expect_false("source_http_request" %in% getNamespaceExports("sampamaisrural"))
  expect_false(exists("sampa_check_updates", asNamespace("sampamaisrural"), inherits = FALSE))
  fake <- http2_fake(list(function(request) { response <- http2_response()(request); response$url <- "https://other.invalid"; response }))
  result <- http2_run(cfg, fake, allow_download = TRUE)
  expect_identical(result$error$code, "invalid_response")
  expect_false(grepl("other.invalid", paste(capture.output(str(result)), collapse = " ")))
})

test_that("1B II rechecks cache before retry and preserves GET validators verbatim", {
  v02_forbid_http()
  cfg <- phase1_check_config(); state <- http2_validated(cfg, etag = '"old"')
  path <- source_safe_path(source_operational_root(cfg), state$validated_content$relative_path)
  fake <- http2_fake(list(function(request) { unlink(path); http2_response(503L)(request) },
    http2_response(headers = list(ETag = 'W/"New-TAG"', `Last-Modified` = "Tue, 01 Jan 2030 00:00:00 GMT"))))
  result <- http2_run(cfg, fake, allow_download = TRUE)
  expect_identical(http2_condition(fake$requests[[1]]), list(`If-None-Match` = '"old"'))
  expect_length(http2_condition(fake$requests[[2]]), 0)
  expect_identical(result$observed_etag_raw, 'W/"New-TAG"')
  expect_identical(result$observed_last_modified_raw, "Tue, 01 Jan 2030 00:00:00 GMT")
  expect_identical(result$outcome, "candidate")
  expect_equal(result$attempts, 2)
  expect_true(all(c("condition", "content", "reused_content", "retrieved_at", "http_status",
    "observed_etag_raw", "observed_last_modified_raw", "error") %in% names(result)))
  expect_null(result$condition)
  expect_identical(source_http_state_lookup(cfg, state$request_identity)$validated_content$etag_raw, '"old"')
  # Explicit force disables condition, but cannot hide a corrupt checksum chain.
  revision <- phase1_check_revision(cfg, state$request_identity)
  writeLines("synthetic corruption", revision)
  fake <- http2_fake(list(http2_response()))
  result <- http2_run(cfg, fake, allow_download = TRUE, force_content = TRUE)
  expect_identical(result$outcome, "blocked"); expect_length(fake$requests, 0)
})

test_that("1B II cache blockers propagate without retries, repair or lock leaks", {
  v02_forbid_http()
  cfg <- phase1_check_config()
  sha <- digest::digest(raw(), algo = "sha256", serialize = FALSE)
  path <- source_safe_path(source_operational_root(cfg), source_content_relative("demo.base", "json", sha))
  dir.create(path, recursive = TRUE)
  fake <- http2_fake(list(http2_response(body = raw())))
  result <- http2_run(cfg, fake, allow_download = TRUE)
  expect_identical(result$outcome, "blocked"); expect_identical(result$error$code, "content_not_regular")
  expect_true(dir.exists(path)); expect_length(fake$requests, 1); expect_length(fake$sleeps, 0)
  expect_false(dir.exists(file.path(source_operational_root(cfg), "locks", "demo.base.lock")))
  # A symlink is never adopted as a content blob, even if its target is regular.
  cfg <- phase1_check_config()
  path <- source_safe_path(source_operational_root(cfg), source_content_relative("demo.base", "json", sha))
  dir.create(dirname(path), recursive = TRUE)
  outside <- withr::local_tempfile(); writeBin(raw(), outside)
  if (!suppressWarnings(file.symlink(outside, path))) skip("Local symlinks unavailable")
  fake <- http2_fake(list(http2_response(body = raw())))
  result <- http2_run(cfg, fake, allow_download = TRUE)
  expect_identical(result$error$code, "symlink_path")
  expect_identical(Sys.readlink(path), outside)
  expect_identical(sha256_file(outside), sha)
  expect_length(fake$requests, 1)
  expect_false(dir.exists(file.path(source_operational_root(cfg), "locks", "demo.base.lock")))
})

test_that("1B II adapter reads bodies only for GET 200 and keeps status errors explicit", {
  v02_forbid_http()
  testthat::local_mocked_bindings(resp_body_raw = function(...) stop("BODY ACCESS FORBIDDEN"), .package = "httr2")
  for (method in c("HEAD", "GET")) for (status in c(302L, 304L, 404L, 429L, 503L)) {
    request <- list(method = method, url = "https://example.invalid/base-sintetica.json",
      headers = list(Accept = "application/json", `Accept-Encoding` = "identity"),
      user_agent = "synthetic", timeout = 3)
    result <- source_http_perform(request, function(req, ...) httr2::response(status, url = req$url, body = charToRaw("SECRET BODY")))
    expect_identical(result$status, status)
    expect_identical(result$body, raw())
  }
  request$method <- "HEAD"
  expect_identical(source_http_perform(request, function(req, ...) httr2::response(200L, req$url, body = charToRaw("ignored")))$body, raw())
})

test_that("1B II recovery preserves the immutable cache collision rule", {
  v02_forbid_http()
  cfg <- phase1_check_config(); bytes <- charToRaw("synthetic accepted")
  state <- http2_validated(cfg, bytes = bytes)
  path <- source_safe_path(source_operational_root(cfg), state$validated_content$relative_path)
  fake <- http2_fake(list(function(request) {
    writeBin(charToRaw("synthetic rejected"), path)
    http2_response(304L)(request)
  }, http2_response(body = bytes)))
  result <- http2_run(cfg, fake, allow_download = TRUE)
  expect_true(result$recovery)
  expect_identical(result$outcome, "blocked")
  expect_identical(result$error$code, "content_hash_mismatch")
  expect_length(fake$requests, 2); expect_length(fake$sleeps, 0)
  expect_identical(readBin(path, "raw", n = 18L), charToRaw("synthetic rejected"))
  expect_false(dir.exists(file.path(source_operational_root(cfg), "locks", "demo.base.lock")))
})

test_that("1B II bounded HEAD retries and ambiguous redirects never enable download", {
  v02_forbid_http()
  fake <- http2_fake(list(http2_response(429L, list(`Retry-After` = "0")), http2_response()))
  cfg <- phase1_check_config(); result <- http2_run(cfg, fake)
  expect_identical(vapply(fake$requests, `[[`, character(1), "method"), c("HEAD", "HEAD"))
  expect_identical(fake$sleeps, 0)
  expect_identical(result$outcome, "metadata"); expect_false(dir.exists(cfg$data_dir))
  fake <- http2_fake(list(http2_response(302L, list(Location = "/one/base-sintetica.json", location = "/two/base-sintetica.json"))))
  result <- http2_run(cfg, fake)
  expect_identical(result$error$code, "invalid_redirect"); expect_length(fake$requests, 1)
  for (status in c(204L, 206L)) {
    fake <- http2_fake(list(http2_response(status)))
    result <- http2_run(cfg, fake, allow_download = TRUE)
    expect_identical(result$error$code, "unexpected_http_status")
    expect_null(result$content); expect_false(dir.exists(cfg$data_dir))
  }
})

test_that("1B II P2 real req_perform leaves Retry-After without Date to our loop", {
  # A fresh child avoids the CORE's req_perform guard without unmocking it in
  # the suite. Its curl boundary is replaced before req_perform can run.
  api <- phase1_check_lock_api()
  for (name in c("validate_source_request_identity", "validate_source_registry")) {
    fun <- get(name, asNamespace("sampamaisrural")); environment(fun) <- api
    assign(name, fun, api)
  }
  results <- callr::r(function(api, registry, identity) {
    library(testthat)
    options(httr2_mock = NULL, httr2_progress = FALSE)
    calls <- 0L; status <- 503L
    local_mocked_bindings(curl_fetch_memory = function(url, handle) {
      calls <<- calls + 1L
      list(url = url, method = "GET", status_code = status, content = raw(), times = c(total = 0),
        headers = charToRaw(paste0("HTTP/1.1 ", status, " Synthetic\r\n",
          "Retry-After: Wed, 02 Jan 2030 03:04:15 GMT\r\n\r\n")))
    }, curl_fetch_disk = function(...) stop("Unexpected disk network boundary"),
      curl_fetch_stream = function(...) stop("Unexpected stream network boundary"), .package = "curl")
    local_mocked_bindings(Sys.sleep = function(...) stop("Unexpected real sleep"), .package = "base")
    request <- list(method = "GET", url = identity$descriptor$absolute_request_url,
      headers = list(Accept = "application/json", `Accept-Encoding` = "identity"),
      user_agent = "synthetic", timeout = 3)
    lapply(c(503L, 429L), function(code) {
      status <<- code; calls <<- 0L
      one <- withCallingHandlers(api$source_http_perform(request),
        httr2_retry = function(cnd) stop("Unexpected httr2 retry processing"))
      one_calls <- calls
      sleeps <- numeric(); per_call <- integer()
      result <- api$source_http_request(list(data_dir = tempfile()), identity, registry,
        allow_download = TRUE, state_lookup = function(...) NULL,
        clock = function() "2030-01-02T03:04:05Z",
        sleep = function(seconds) { sleeps <<- c(sleeps, seconds) },
        performer = function(request) {
          before <- calls
          response <- withCallingHandlers(api$source_http_perform(request),
            httr2_retry = function(cnd) stop("Unexpected httr2 retry processing"))
          per_call <<- c(per_call, calls - before)
          response
        })
      list(status = one$status, headers = one$headers, one_calls = one_calls,
        per_call = per_call, calls = calls, sleeps = sleeps, result = result)
    })
  }, args = list(api, phase1_registry(), phase1_check_identity()), timeout = 30)
  for (i in seq_along(results)) {
    x <- results[[i]]
    expect_identical(x$status, c(503L, 429L)[i])
    expect_false("date" %in% tolower(names(x$headers)))
    expect_identical(x$one_calls, 1L)
    expect_identical(x$per_call, rep(1L, 3))
    expect_identical(x$calls, 4L)
    expect_identical(x$sleeps, c(10, 10))
    expect_identical(x$result$attempts, 3L)
    expect_identical(x$result$http_status, x$status)
    expect_identical(x$result$outcome, "http_error")
    expect_identical(x$result$error$code, "http_unavailable")
  }
})

test_that("1B II P2 transport URL equivalence preserves identity and rejects real changes", {
  v02_forbid_http()
  registry <- phase1_registry()
  # Synthetic support resource: no report slug is imposed on its path.
  registry$sources[[3]] <- list(source_id = "demo.terms", catalog_slug = NULL, name = "Synthetic terms",
    role = "terms", enabled = TRUE, overlaps_with = character(), representations = list(html = list(
      parser = "html_document_v1", contract = "terms-v1.yml", filename = "terms.html",
      endpoint_config = "terms_url", default_url = "https://example.invalid")))
  pairs <- list(
    c("HTTPS://example.invalid/base-sintetica.json", "https://example.invalid/base-sintetica.json", "demo.base", "json"),
    c("https://EXAMPLE.INVALID/base-sintetica.json", "https://example.invalid/base-sintetica.json", "demo.base", "json"),
    c("https://example.invalid", "https://example.invalid/", "demo.terms", "html"),
    c("HTTPS://EXAMPLE.INVALID?x=1", "https://example.invalid/?x=1", "demo.terms", "html"))
  for (pair in pairs) {
    original <- source_request_identity(pair[3], pair[4], pair[1], registry)
    normalized <- source_request_identity(pair[3], pair[4], pair[2], registry)
    fake <- http2_fake(list(function(request) {
      response <- http2_response()(request); response$url <- pair[2]; response
    }))
    result <- source_http_request(phase1_check_config(), original, registry, performer = fake$perform)
    expect_identical(result$outcome, "metadata")
    expect_null(result$error)
    expect_identical(result$requested_identity, original)
    expect_identical(result$identity, original)
    expect_identical(result$requested_url, pair[1])
    expect_identical(result$effective_url, pair[2])
    expect_false(identical(original$sha256, normalized$sha256))
    expect_true(source_http_urls_equivalent(pair[2], pair[1], registry$url_policy))
  }
  requested <- "https://example.invalid/a/base-sintetica.json?x=1"
  bad <- c("https://example.invalid/a/base-sintetica.json?x=2",
    "https://example.invalid/b/base-sintetica.json?x=1", "https://other.invalid/a/base-sintetica.json?x=1",
    "https://example.invalid:8443/a/base-sintetica.json?x=1", "https://example.invalid:443/a/base-sintetica.json?x=1",
    "http://example.invalid/a/base-sintetica.json?x=1", "https://user@example.invalid/a/base-sintetica.json?x=1",
    "https://example.invalid/a/other.json?x=1", "https://example.invalid/a/base-sintetica.csv?x=1",
    "https://example.invalid/a/base-sintetica.json?x=1#fragment", "https://example.invalid/a/../a/base-sintetica.json?x=1",
    "https://example.invalid/a/%62ase-sintetica.json?x=1")
  original <- source_request_identity("demo.base", "json", requested, registry)
  for (effective in bad) {
    fake <- http2_fake(list(function(request) {
      response <- http2_response()(request); response$url <- effective; response
    }))
    result <- source_http_request(phase1_check_config(), original, registry, performer = fake$perform)
    expect_identical(result$error$code, "invalid_response", info = effective)
    expect_identical(result$identity, original)
  }
  expect_false(source_http_urls_equivalent("https://example.invalid?", "https://example.invalid/", registry$url_policy))
  expect_false(source_http_urls_equivalent("https://example.invalid/?a=1&b=2", "https://example.invalid/?b=2&a=1", registry$url_policy))
})

test_that("1B II P2 redirects resolve raw authority and path without erasing traversal", {
  v02_forbid_http()
  registry <- phase1_registry()
  registry$sources[[3]] <- list(source_id = "demo.terms", catalog_slug = NULL, name = "Synthetic terms",
    role = "terms", enabled = TRUE, overlaps_with = character(), representations = list(html = list(
      parser = "html_document_v1", contract = "terms-v1.yml", filename = "terms.html",
      endpoint_config = "terms_url", default_url = "https://example.invalid")))
  cases <- list(
    c("https://example.invalid?x=1", "/terms", "https://example.invalid/terms"),
    c("https://example.invalid", "terms", "https://example.invalid/terms"),
    c("https://example.invalid/a/report.json?x=1", "next.json", "https://example.invalid/a/next.json"),
    c("HTTPS://example.invalid/a/report.json", "next.json", "HTTPS://example.invalid/a/next.json"),
    c("HTTPS://example.invalid?x=1", "/terms", "HTTPS://example.invalid/terms"),
    c("https://example.invalid?x=1", "?x=2", "https://example.invalid?x=2"),
    c("https://example.invalid/a/report.json?x=1", "?x=2", "https://example.invalid/a/report.json?x=2"),
    c("https://example.invalid", "//example.invalid/terms", "https://example.invalid/terms"),
    c("https://example.invalid?x=1", "https://example.invalid/terms?y=2", "https://example.invalid/terms?y=2"))
  for (case in cases) {
    original <- source_request_identity("demo.terms", "html", case[1], registry)
    expected <- source_request_identity("demo.terms", "html", case[3], registry)
    expect_identical(source_http_redirect_identity(original, case[2], registry), expected)
    fake <- http2_fake(list(http2_response(302L, list(Location = case[2])), http2_response()))
    lookups <- character()
    result <- source_http_request(phase1_check_config(), original, registry, allow_download = TRUE,
      performer = fake$perform, clock = phase1_check_clock,
      state_lookup = function(config, identity) { lookups <<- c(lookups, identity$sha256); NULL })
    expect_identical(result$outcome, "candidate")
    expect_identical(result$requested_identity, original)
    expect_identical(result$identity, expected)
    expect_identical(fake$requests[[2]]$url, case[3])
    expect_identical(lookups, c(original$sha256, expected$sha256))
    expect_length(http2_condition(fake$requests[[2]]), 0)
  }
  original <- source_request_identity("demo.terms", "html", "HTTPS://example.invalid?x=1", registry)
  for (location in c("../terms", "./terms", "%2e%2e/terms", "/a/../terms", "//user@example.invalid/terms",
      "//other.invalid/terms", "http://example.invalid/terms", "#fragment")) {
    expect_error(source_http_redirect_identity(original, location, registry), "invalid_redirect", class = "source_http_error")
  }
})
