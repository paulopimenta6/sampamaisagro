# B1b uses only synthetic bytes, isolated directories and injected HTTP in setup.
b1b_bytes <- function(name = "report.json") {
  path <- phase1_path(name)
  readBin(path, "raw", file.info(path)$size)
}
b1b_response <- function(status = 200L, headers = list(), bytes = b1b_bytes()) {
  force(status); force(headers); force(bytes)
  function(req) httr2::response(status, req$url, method = req$method, headers = headers, body = bytes)
}
b1b_observe <- function(cfg, responses = list(b1b_response()), identity = phase1_check_identity(),
                        download = TRUE, joint = FALSE, ...) {
  count <- 0L
  source_observation_representation(cfg, identity, phase1_registry(), allow_download = download,
    joint_acceptance_required = joint, execute = function(req, ...) {
      count <<- count + 1L
      if (count > length(responses)) stop("Unexpected synthetic B1b setup request")
      responses[[count]](req)
    }, clock = function() "2030-01-03T00:00:00Z", sleep = function(seconds) NULL, ...)
}
b1b_seed <- function(cfg, identity = phase1_check_identity(), etag = '"old"', modified = NULL,
                     method = "GET", error = NULL) {
  d <- identity$descriptor
  blob <- store_source_content(cfg, d$source_id, d$representation, b1b_bytes())$content
  state <- source_state_candidate(new_source_state(identity), blob, clock = phase1_check_clock)
  state <- source_state_promote(state, phase1_check_validation(), phase1_check_clock)
  state$validated_content[c("etag_raw", "last_modified_raw")] <- list(etag, modified)
  state$validated_content$conditional_reuse_allowed <- TRUE
  state$validated_content$conditional_reuse_restrictions <- list()
  state$last_http_observation <- list(observed_at = phase1_check_clock(), method = method,
    request_url = d$absolute_request_url, http_status = 200L, etag_raw = etag, last_modified_raw = modified)
  state["last_error"] <- list(error)
  phase1_check_commit(cfg, identity, state, type = "content_validated", sha = blob$sha256)
}
b1b_forbid <- function(envir = parent.frame()) {
  names <- c("source_http_request", "source_http_perform", "source_observation_representation",
    "store_source_content", "validate_source_pair", "reconcile_source_catalog", "collect_sampa_data",
    "prepare_equipment_data", "validate_source_payload")
  bindings <- stats::setNames(lapply(names, function(name) {
    force(name); function(...) stop(paste("B1b forbidden", name))
  }), names)
  do.call(testthat::local_mocked_bindings, c(bindings, list(.package = "sampamaisrural", .env = envir)))
}
b1b_persist <- function(cfg, observation, check_id = "synthetic-check", ...) {
  b1b_forbid()
  source_persistence_representation(cfg, observation, check_id, clock = phase1_check_clock, ...)
}
b1b_last <- function(cfg, identity = phase1_check_identity()) tail(read_source_revisions(cfg, identity), 1)[[1]]
b1b_equal <- function(actual, expected) expect_identical(source_canonical_json(actual), source_canonical_json(expected))
b1b_files <- function(cfg) {
  files <- list.files(cfg$data_dir, recursive = TRUE, all.files = TRUE, full.names = TRUE)
  stats::setNames(vapply(files, sha256_file, character(1)), files)
}

test_that("B1b accepts 200 in exactly one terminal revision and verifies its receipt", {
  cfg <- phase1_check_config(); obs <- b1b_observe(cfg, list(b1b_response(headers = list(ETag = '"new"'))))
  before <- b1b_files(cfg); out <- b1b_persist(cfg, obs)
  expect_identical(out$status, "initialized"); expect_identical(out$content_changed, NA)
  expect_identical(out$observation, obs); expect_identical(out$persistence$outcome, "committed")
  records <- read_source_revisions(cfg, phase1_check_identity()); expect_length(records, 1L)
  r <- records[[1]]; s <- r$state_after
  expect_identical(r$event$type, "content_validated"); expect_identical(r$event$check_id, "synthetic-check")
  expect_identical(r$event$occurred_at, obs$context$checked_at)
  expect_identical(s$validated_content$sha256, obs$content$sha256)
  expect_identical(s$latest_candidate$sha256, obs$content$sha256)
  expect_identical(s$validated_content$retrieved_at, obs$content$retrieved_at)
  expect_identical(s$validated_content$validated_at, obs$context$checked_at)
  expect_identical(s$validated_content$etag_raw, '"new"'); expect_true(s$validated_content$conditional_reuse_allowed)
  expect_length(s$validated_content$conditional_reuse_restrictions, 0L)
  expect_null(s$last_confirmed_content_change)
  expect_identical(s$last_check$started_at, obs$context$started_at)
  expect_identical(s$last_check$finished_at, obs$context$checked_at)
  expect_identical(s$registry_revision_seen, obs$context$registry_revision)
  expect_identical(s$last_http_observation$event_id, r$event$event_id)
  receipt <- out$persistence$receipt
  expect_setequal(names(receipt), c("source_id", "representation", "request_identity_sha256",
    "state_revision", "event_id", "check_id", "type", "record_sha256"))
  expect_identical(receipt$record_sha256, source_record_checksum(r)); expect_equal(receipt$state_revision, 1)
  expect_identical(receipt$event_id, r$event$event_id)
  expect_identical(b1b_files(cfg)[names(before)], before)
  expect_false(any(grepl("current.json|snapshot|processed|manifest", names(b1b_files(cfg)))))
  expect_false(dir.exists(file.path(source_operational_root(cfg), "locks/demo.base.lock")))
  expect_error(source_persistence_outcome("partial"), "invalid_persistence_outcome")
})

test_that("B1b only accepted differing bytes confirm change, and candidates preserve it", {
  cfg <- phase1_check_config(); old <- b1b_seed(cfg, error = list(observed_at = phase1_check_clock(),
    kind = "validation", code = "schema_breaking", resolved_at = NULL))
  same <- b1b_observe(cfg); out <- b1b_persist(cfg, same, "same")
  expect_identical(out$status, "content_unchanged"); expect_false(out$content_changed)
  s <- b1b_last(cfg)$state_after; expect_null(s$last_confirmed_content_change)
  expect_identical(s$last_error$resolved_at, same$context$checked_at)
  expect_null(s$validated_content$etag_raw) # New 200 never inherits old headers.
  expect_false(s$validated_content$conditional_reuse_allowed)
  changed <- b1b_observe(cfg, list(b1b_response(bytes = b1b_bytes("additive.json"))))
  expect_identical(b1b_persist(cfg, changed, "changed")$status, "content_changed")
  r <- b1b_last(cfg); change <- r$state_after$last_confirmed_content_change
  expect_identical(change$previous_sha256, old$validated_content$sha256)
  expect_identical(change$observed_sha256, changed$content$sha256)
  expect_true(change$candidate_accepted); expect_identical(change$observed_at, changed$content$retrieved_at)
  expect_identical(change$event_id, r$event$event_id)
  accepted <- r$state_after$validated_content
  bad <- b1b_observe(cfg, list(b1b_response(bytes = b1b_bytes("missing-required.json"))))
  out <- b1b_persist(cfg, bad, "bad")
  expect_identical(out$status, "incompatible_content")
  r <- b1b_last(cfg); expect_identical(r$event$type, "candidate_stored")
  expect_identical(r$state_after$latest_candidate$validation$decision, "block")
  b1b_equal(r$state_after$validated_content, accepted)
  b1b_equal(r$state_after$last_confirmed_content_change, change)
  expect_identical(r$state_after$last_error$kind, "validation")
  expect_null(r$state_after$last_error$resolved_at)
  expect_length(read_source_revisions(cfg, phase1_check_identity()), 4L)
})

test_that("B1b 304 revalidates historical content without promoting the latest candidate", {
  cfg <- phase1_check_config(); old <- b1b_seed(cfg)
  bad <- b1b_observe(cfg, list(b1b_response(bytes = b1b_bytes("missing-required.json"))))
  b1b_persist(cfg, bad, "bad"); before <- b1b_last(cfg)$state_after
  obs <- b1b_observe(cfg, list(b1b_response(304L)))
  out <- b1b_persist(cfg, obs, "revalidate"); r <- b1b_last(cfg); after <- r$state_after
  expect_identical(out$status, "not_modified"); expect_identical(out$content_changed, NA)
  expect_identical(r$event$type, "content_validated")
  fields <- c("sha256", "bytes", "relative_path", "retrieved_at")
  b1b_equal(after$validated_content[fields], old$validated_content[fields])
  b1b_equal(after$latest_candidate, before$latest_candidate)
  expect_identical(after$validated_content$validated_at, obs$context$checked_at)
  expect_identical(after$validated_content$etag_raw, '"old"')
  expect_null(after$last_http_observation$etag_raw)
  expect_identical(after$last_error$resolved_at, obs$context$checked_at)
  expect_null(after$last_confirmed_content_change)
  strict <- phase1_contract(); strict$version <- 2L; strict$schema$properties$partners$min_items <- 100L
  obs <- b1b_observe(cfg, list(b1b_response(304L)), contract_loader = function(...) strict)
  out <- b1b_persist(cfg, obs, "strict"); failed <- b1b_last(cfg)
  expect_identical(out$status, "incompatible_content")
  expect_identical(failed$event$type, "state_validation_failed"); expect_identical(failed$event$decision, "block")
  expect_identical(failed$event$content_sha256, old$validated_content$sha256)
  for (key in c("validated_content", "latest_candidate", "last_confirmed_content_change")) b1b_equal(failed$state_after[[key]], after[[key]])
  expect_identical(out$observation$validation$contract_version, 2L)
  expect_identical(failed$state_after$last_check$status, "incompatible_content")
})

test_that("B1b HEAD and known failures only persist terminal operational metadata", {
  fail <- function(class) function(req) stop(structure(list(message = "SYNTHETIC SECRET", call = NULL),
    class = c(class, "curl_error", "error", "condition")))
  cases <- list(head_same = list(b1b_response(headers = list(ETag = '"old"'))),
    head_changed = list(b1b_response(headers = list(ETag = '"new"'))), head_none = list(b1b_response()),
    http404 = list(b1b_response(404L)), timeout = rep(list(fail("curl_error_operation_timedout")), 3),
    tls = list(fail("curl_error_peer_failed_verification")), protocol = list(b1b_response(206L)))
  expected <- c(head_same = "indeterminate", head_changed = "metadata_changed", head_none = "indeterminate",
    http404 = "source_unavailable", timeout = "source_unavailable", tls = "check_failed", protocol = "check_failed")
  for (name in names(cases)) {
    cfg <- phase1_check_config(); old <- b1b_seed(cfg, method = "HEAD", error = list(observed_at = phase1_check_clock(),
      code = "schema_breaking", kind = "validation", resolved_at = NULL))
    obs <- b1b_observe(cfg, cases[[name]], download = !startsWith(name, "head"))
    out <- b1b_persist(cfg, obs); r <- b1b_last(cfg)
    expect_identical(out$status, unname(expected[[name]]), info = name)
    expect_identical(out$content_changed, NA); expect_identical(out$persistence$outcome, "committed")
    expect_identical(r$event$type, "check_finished"); expect_null(r$event$content_sha256)
    for (key in c("validated_content", "latest_candidate", "last_confirmed_content_change")) b1b_equal(r$state_after[[key]], old[[key]])
    if (name %in% c("timeout", "tls")) b1b_equal(r$state_after$last_http_observation, old$last_http_observation)
    if (startsWith(name, "head")) b1b_equal(r$state_after$last_error, old$last_error)
    expect_false(grepl("SYNTHETIC SECRET", source_canonical_json(r), fixed = TRUE))
  }
})

test_that("B1b idempotence precedes stale checks and rejects check ID collisions", {
  cfg <- phase1_check_config(); obs <- b1b_observe(cfg)
  first <- b1b_persist(cfg, obs, "once"); files <- b1b_files(cfg)
  again <- b1b_persist(cfg, obs, "once")
  expect_identical(again$persistence$receipt, first$persistence$receipt)
  expect_identical(again$persistence$reason_codes, "already_committed")
  expect_identical(b1b_files(cfg), files)
  other <- b1b_observe(cfg, download = FALSE); b1b_persist(cfg, other, "later")
  replay <- b1b_persist(cfg, obs, "once")
  expect_identical(replay$persistence$receipt, first$persistence$receipt)
  expect_length(read_source_revisions(cfg, phase1_check_identity()), 2L)
  for (key in c("reason", "time", "registry", "validation")) {
    changed <- obs
    if (key == "reason") changed$reason_codes <- "different_reason"
    if (key == "time") changed$context$checked_at <- "2030-01-04T00:00:00Z"
    if (key == "registry") changed$context$registry_revision <- "synthetic-2"
    if (key == "validation") changed$validation$classification <- "additive"
    out <- b1b_persist(cfg, changed, "once")
    expect_identical(out$status, "blocked"); expect_identical(out$persistence$outcome, "not_attempted")
    expect_identical(out$persistence$error$code, "check_id_conflict")
  }
  out <- b1b_persist(cfg, obs, "new-check")
  expect_identical(out$persistence$error$code, "stale_state_revision")
  expect_length(read_source_revisions(cfg, phase1_check_identity()), 2L)
  head <- other; head$context$state_revision <- NULL
  expect_identical(source_persistence_event(head, "once")$event_id, source_persistence_event(obs, "once")$event_id)
})

test_that("B1b rereads under lock and rejects concurrent changes even with identical bytes", {
  cfg <- phase1_check_config(); old <- b1b_seed(cfg); obs <- b1b_observe(cfg)
  acquire <- acquire_source_lock; reads <- 0L; read <- read_source_revisions
  testthat::local_mocked_bindings(read_source_revisions = function(config, identity) {
    expect_true(dir.exists(file.path(source_operational_root(config), "locks/demo.base.lock")))
    reads <<- reads + 1L; read(config, identity)
  }, .package = "sampamaisrural")
  # Use the original lock function for the competing synthetic writer.
  testthat::local_mocked_bindings(acquire_source_lock = function(...) {
    held <- acquire(cfg, "demo.base")
    phase1_check_commit(cfg, old$request_identity, old, 2L, "check_finished", lock = held)
    release_source_lock(cfg, held)
    acquire(...)
  }, .package = "sampamaisrural")
  out <- b1b_persist(cfg, obs)
  expect_identical(out$status, "blocked"); expect_identical(out$persistence$error$code, "stale_state_revision")
  expect_gt(reads, 0L)
  expect_length(read(cfg, old$request_identity), 2L)
})

test_that("B1b borrowed locks remain owned and invalid locks never write", {
  cfg <- phase1_check_config(); obs <- b1b_observe(cfg)
  held <- acquire_source_lock(cfg, "demo.base")
  busy <- b1b_persist(cfg, obs)
  expect_identical(busy$status, "blocked"); expect_true(busy$retryable)
  expect_identical(busy$persistence$error$code, "lock_busy")
  wrong <- held; wrong$owner$token <- "wrong"
  expect_identical(b1b_persist(cfg, obs, lock = wrong)$persistence$error$code, "lock_not_owned")
  other <- acquire_source_lock(cfg, "demo.subset")
  expect_identical(b1b_persist(cfg, obs, lock = other)$persistence$error$code, "lock_identity_mismatch")
  release_source_lock(cfg, other)
  local({
    testthat::local_mocked_bindings(acquire_source_lock = function(...) stop("nested acquisition"),
      release_source_lock = function(...) stop("borrowed release"), .package = "sampamaisrural")
    expect_identical(b1b_persist(cfg, obs, lock = held)$persistence$outcome, "committed")
    expect_true(assert_source_lock(cfg, "demo.base", held))
  })
  expect_true(release_source_lock(cfg, held))
})

test_that("B1b joint observations including failures consume no terminal event or lock", {
  for (response in list(b1b_response(), b1b_response(404L), b1b_response(bytes = b1b_bytes("missing-required.json")))) {
    cfg <- phase1_check_config(); obs <- b1b_observe(cfg, list(response), joint = TRUE); before <- b1b_files(cfg)
    local({
      testthat::local_mocked_bindings(with_source_lock = function(...) stop("joint lock"),
        source_state_event = function(...) stop("joint event"), commit_source_event = function(...) stop("joint commit"),
        .package = "sampamaisrural")
      out <- b1b_persist(cfg, obs)
      expect_identical(out$persistence$outcome, "not_attempted")
      expect_identical(out$persistence$reason_codes, "pending_joint_acceptance")
      expect_null(out$persistence$receipt); expect_identical(out$observation, obs)
      expect_identical(b1b_files(cfg), before)
    })
  }
})

test_that("B1b corrupt chains and missing final content references block without repair", {
  cfg <- phase1_check_config(); old <- b1b_seed(cfg); obs <- b1b_observe(cfg)
  path <- phase1_check_revision(cfg, old$request_identity); writeLines("synthetic corruption", path)
  before <- b1b_files(cfg); out <- b1b_persist(cfg, obs)
  expect_identical(out$status, "blocked"); expect_identical(out$persistence$outcome, "not_attempted")
  expect_identical(b1b_files(cfg), before)
  blocked <- b1b_observe(cfg)
  expect_identical(b1b_persist(cfg, blocked)$persistence$reason_codes, "observation_blocked")
  for (kind in c("absent", "corrupt")) {
    cfg <- phase1_check_config(); obs <- b1b_observe(cfg)
    path <- source_safe_path(source_operational_root(cfg), obs$content$relative_path)
    if (kind == "absent") unlink(path) else writeBin(charToRaw("synthetic damage"), path)
    before <- b1b_files(cfg); out <- b1b_persist(cfg, obs)
    expect_identical(out$status, "blocked"); expect_false(out$retryable)
    expect_identical(out$persistence$outcome, "not_attempted"); expect_null(out$persistence$receipt)
    expect_length(read_source_revisions(cfg, phase1_check_identity()), 0L)
    expect_identical(b1b_files(cfg), before)
  }
})

test_that("B1b reconciles known failures before and after rename without blind retries", {
  for (point in c("before_temp_write", "after_temp_write", "before_rename", "after_rename")) {
    cfg <- phase1_check_config(); obs <- b1b_observe(cfg); calls <- 0L
    hook <- function(context) { calls <<- calls + 1L; source_state_block("rename_failed") }
    out <- b1b_persist(cfg, obs, hooks = stats::setNames(list(hook), point))
    committed <- point == "after_rename"
    expect_identical(out$persistence$outcome, if (committed) "committed" else "failed", info = point)
    expect_identical(out$status, if (committed) "initialized" else "check_failed")
    expect_identical(calls, 1L)
    expect_length(read_source_revisions(cfg, phase1_check_identity()), if (committed) 1L else 0L)
    before <- b1b_files(cfg)
    again <- b1b_persist(cfg, obs)
    expect_identical(again$persistence$outcome, "committed")
    expect_length(read_source_revisions(cfg, phase1_check_identity()), 1L)
    expect_identical(b1b_files(cfg)[names(before)], before) # Includes preserved .pending evidence.
  }
  cfg <- phase1_check_config(); obs <- b1b_observe(cfg)
  hooks <- list(before_rename = function(context) {
    writeLines("synthetic competing corrupt record", context$destination)
    source_state_block("destination_exists")
  })
  out <- b1b_persist(cfg, obs, hooks = hooks)
  expect_identical(out$status, "check_failed"); expect_identical(out$persistence$outcome, "uncertain")
  expect_null(out$persistence$receipt)
  expect_identical(readLines(phase1_check_revision(cfg, phase1_check_identity())), "synthetic competing corrupt record")
})

test_that("B1b never demotes a proved commit on release or subsequent integrity failure", {
  cfg <- phase1_check_config(); obs <- b1b_observe(cfg)
  local({
    testthat::local_mocked_bindings(release_source_lock = function(...) source_state_block("lock_release_failed"),
      .package = "sampamaisrural")
    out <- b1b_persist(cfg, obs)
    expect_identical(out$status, "check_failed"); expect_identical(out$persistence$outcome, "committed")
    expect_identical(out$persistence$error$code, "lock_release_failed")
    expect_identical(out$persistence$receipt$record_sha256, b1b_last(cfg)$record_sha256)
  })
  expect_true(dir.exists(file.path(source_operational_root(cfg), "locks/demo.base.lock")))
  cfg <- phase1_check_config(); obs <- b1b_observe(cfg)
  hooks <- list(after_rename = function(context) {
    unlink(source_safe_path(source_operational_root(cfg), obs$content$relative_path))
  })
  out <- b1b_persist(cfg, obs, hooks = hooks)
  expect_identical(out$status, "check_failed"); expect_identical(out$persistence$outcome, "committed")
  expect_identical(out$persistence$error$code, "content_missing")
  expect_identical(out$persistence$receipt$record_sha256, b1b_last(cfg)$record_sha256)
})

test_that("B1b unknown programming errors propagate even after a write", {
  bug <- structure(list(message = "synthetic programming error", call = NULL), class = c("b1b_bug", "error", "condition"))
  for (point in c("before_temp_write", "after_rename")) {
    cfg <- phase1_check_config(); obs <- b1b_observe(cfg)
    hooks <- stats::setNames(list(function(context) stop(bug)), point)
    expect_identical(tryCatch(b1b_persist(cfg, obs, hooks = hooks), b1b_bug = identity), bug)
    expect_false(dir.exists(file.path(source_operational_root(cfg), "locks/demo.base.lock")))
    expect_length(read_source_revisions(cfg, phase1_check_identity()), if (point == "after_rename") 1L else 0L)
    expect_identical(b1b_persist(cfg, obs)$persistence$outcome, "committed")
    expect_length(read_source_revisions(cfg, phase1_check_identity()), 1L)
  }
  cfg <- phase1_check_config(); obs <- b1b_observe(cfg)
  testthat::local_mocked_bindings(source_persistence_transition = function(...) stop(bug), .package = "sampamaisrural")
  expect_identical(tryCatch(b1b_persist(cfg, obs), b1b_bug = identity), bug)
})

test_that("B1b 304 validator inheritance is conservative and HTTP evidence stays literal", {
  modified <- "Tue, 01 Jan 2030 00:00:00 GMT"
  cases <- list(omitted = list(), changed = list(ETag = '"new"'),
    invalid = list(ETag = "invalid"), duplicate = list(ETag = '"a"', etag = '"b"'),
    modified = list(`Last-Modified` = "Wed, 02 Jan 2030 00:00:00 GMT"))
  for (name in names(cases)) {
    cfg <- phase1_check_config(); b1b_seed(cfg, modified = modified)
    obs <- b1b_observe(cfg, list(b1b_response(304L, cases[[name]])))
    b1b_persist(cfg, obs); s <- b1b_last(cfg)$state_after
    expect_identical(s$last_http_observation$etag_raw, obs$transport$observed_etag_raw)
    expect_identical(s$last_http_observation$last_modified_raw, obs$transport$observed_last_modified_raw)
    invalid <- name %in% c("invalid", "duplicate")
    expect_identical(s$validated_content$conditional_reuse_allowed, !invalid)
    expect_identical(s$validated_content$etag_raw, if (invalid) NULL else if (name == "changed") '"new"' else '"old"')
    expect_identical(s$validated_content$last_modified_raw, if (name == "modified") cases[[name]][[1L]] else modified)
    expect_false("http_policy_not_implemented" %in% s$validated_content$conditional_reuse_restrictions)
  }
  # Invalid header on an earlier attempt cannot invalidate an explicit valid terminal header.
  cfg <- phase1_check_config(); b1b_seed(cfg)
  obs <- b1b_observe(cfg, list(b1b_response(503L, list(ETag = "invalid")), b1b_response(304L, list(ETag = '"final"'))))
  b1b_persist(cfg, obs); expect_true(b1b_last(cfg)$state_after$validated_content$conditional_reuse_allowed)
})

test_that("B1b recovery can replace absent old blobs but retained references must exist", {
  for (accepted in c(TRUE, FALSE)) {
    cfg <- phase1_check_config(); old <- b1b_seed(cfg)
    path <- source_safe_path(source_operational_root(cfg), old$validated_content$relative_path)
    first <- function(req) { unlink(path); b1b_response(304L)(req) }
    bytes <- b1b_bytes(if (accepted) "additive.json" else "missing-required.json")
    obs <- b1b_observe(cfg, list(first, b1b_response(bytes = bytes)))
    expect_true(obs$transport$recovery)
    out <- b1b_persist(cfg, obs)
    expect_identical(out$status, if (accepted) "content_changed" else "blocked")
    expect_identical(out$persistence$outcome, if (accepted) "committed" else "not_attempted")
    expect_length(read_source_revisions(cfg, old$request_identity), if (accepted) 2L else 1L)
    expect_false(file.exists(path))
  }
})

test_that("B1b redirects persist only the effective identity and never a prior hop response", {
  cfg <- phase1_check_config(); a <- phase1_check_identity(); b <- phase1_check_identity(query = "?target=1")
  old <- b1b_seed(cfg, a); before <- sha256_file(phase1_check_revision(cfg, a))
  obs <- b1b_observe(cfg, list(b1b_response(302L, list(Location = "?target=1")), b1b_response()))
  out <- b1b_persist(cfg, obs)
  expect_identical(out$persistence$receipt$request_identity_sha256, b$sha256)
  expect_identical(sha256_file(phase1_check_revision(cfg, a)), before)
  expect_identical(b1b_last(cfg, b)$state_after$last_http_observation$request_url, b$descriptor$absolute_request_url)
  expect_equal(b1b_last(cfg, b)$state_after$last_http_observation$http_status, 200L)
  cfg <- phase1_check_config()
  # Inject typed curl timeout so B1a's normal adapter policy supplies the observation.
  failure <- function(req) stop(structure(list(message = "synthetic", call = NULL),
    class = c("curl_error_operation_timedout", "curl_error", "error", "condition")))
  obs <- b1b_observe(cfg, c(list(b1b_response(302L, list(Location = "?target=1"))), rep(list(failure), 3L)))
  b1b_persist(cfg, obs)
  expect_length(read_source_revisions(cfg, a), 0L)
  expect_null(b1b_last(cfg, b)$state_after$last_http_observation)
})

test_that("B1b commit primitive composes JSON and CSV under one external source lock", {
  cfg <- phase1_check_config(); json <- b1b_observe(cfg, download = FALSE)
  csv <- b1b_observe(cfg, identity = phase1_check_identity("csv"), download = FALSE, joint = TRUE)
  held <- acquire_source_lock(cfg, "demo.base")
  b1b_forbid()
  testthat::local_mocked_bindings(acquire_source_lock = function(...) stop("nested lock"), .package = "sampamaisrural")
  pj <- source_persistence_prepare(cfg, json, "one-cycle", held)
  # Exercise only the existing commit boundary for C's future preparation;
  # this is a synthetic HEAD event, not CSV acceptance or operational pairing.
  event <- source_persistence_event(csv, "one-cycle")
  pc <- list(identity = csv$context$effective_identity, generation = 0L, head_sha256 = NULL,
    event = event, state_after = source_persistence_transition(NULL, csv, event))
  expect_identical(source_persistence_commit(cfg, pj, held)$outcome, "committed")
  expect_identical(source_persistence_commit(cfg, pc, held)$outcome, "committed")
  expect_true(assert_source_lock(cfg, "demo.base", held))
  expect_length(read_source_revisions(cfg, phase1_check_identity()), 1L)
  expect_length(read_source_revisions(cfg, phase1_check_identity("csv")), 1L)
  expect_error(source_persistence_commit(cfg, pj, held), "stale_state_revision")
  expect_true(release_source_lock(cfg, held))
  expect_false(dir.exists(file.path(source_operational_root(cfg), "locks/demo.base.lock")))
})

test_that("B1b invalid observations fail before locking and the helpers have no future-unit calls", {
  cfg <- phase1_check_config(); obs <- b1b_observe(cfg)
  local({
    testthat::local_mocked_bindings(with_source_lock = function(...) stop("unexpected lock"), .package = "sampamaisrural")
    expect_error(b1b_persist(cfg, obs, "bad check"), "invalid_check_id")
    bad <- obs; bad$content$sha256 <- paste(rep("a", 64), collapse = "")
    expect_error(b1b_persist(cfg, bad), "invalid_content_reference")
    bad <- obs; bad$planned_event_type <- "candidate_stored"
    expect_error(b1b_persist(cfg, bad), "invalid_content_observation")
    bad <- obs; bad$context$effective_identity <- phase1_check_identity(query = "?wrong=1")
    expect_error(b1b_persist(cfg, bad), "invalid_terminal_transport")
  })
  ns <- asNamespace("sampamaisrural"); symbols <- ls(ns, pattern = "^source_persistence_")
  calls <- unique(unlist(lapply(symbols, function(name) all.names(body(get(name, ns))))))
  expect_false(any(c("source_http_request", "source_http_perform", "Sys.sleep", "validate_source_pair",
    "reconcile_source_catalog", "collect_sampa_data", "prepare_equipment_data", "store_source_content",
    "writeBin", "writeLines", "file.rename", "unlink", "source_atomic_file") %in% calls))
  expect_false(any(symbols %in% getNamespaceExports(ns)))
  expect_false(exists("sampa_check_updates", ns, inherits = FALSE))
})

test_that("B1b HEAD metadata round-trip distinguishes invalid validators from absence", {
  first_date <- "Tue, 01 Jan 2030 00:00:00 GMT"
  next_date <- "Wed, 02 Jan 2030 00:00:00 GMT"
  cases <- list(invalid = list(ETag = "invalid"), duplicate = list(ETag = '"a"', etag = '"b"'),
    absent = list(), valid = list(ETag = '"same"'))
  for (name in names(cases)) {
    cfg <- phase1_check_config(); identity <- phase1_check_identity()
    headers <- c(cases[[name]], list(`Last-Modified` = first_date))
    next_headers <- c(if (name == "valid") cases[[name]] else list(), list(`Last-Modified` = next_date))
    ambiguous <- name %in% c("invalid", "duplicate")
    original <- list(identity_sha256 = identity$sha256, method = "HEAD", headers = headers)
    current <- list(identity_sha256 = identity$sha256, method = "HEAD", headers = next_headers)
    direct <- source_update_compare_metadata(original, current)
    expect_identical(direct, if (ambiguous) NA else TRUE, info = name)
    first <- b1b_observe(cfg, list(b1b_response(headers = headers)), download = FALSE)
    expect_identical(any(vapply(first$transport$diagnostics, function(d) identical(d$code, "invalid_validator"),
      logical(1))), ambiguous)
    expect_identical("last_http_invalid_validator" %in% first$reason_codes, ambiguous)
    expect_identical(b1b_persist(cfg, first)$persistence$outcome, "committed")
    record <- b1b_last(cfg); state <- record$state_after
    expect_identical(record$event$type, "check_finished")
    expect_identical("last_http_invalid_validator" %in% state$last_check$reason_codes, ambiguous)
    expect_identical(state$last_http_observation$etag_raw, if (name == "valid") '"same"' else NULL)
    expect_identical(state$last_http_observation$last_modified_raw, first_date)
    expect_null(state$validated_content)
    next_check <- b1b_observe(cfg, list(b1b_response(headers = next_headers)), download = FALSE)
    expect_identical(next_check$metadata_changed, direct, info = name)
    expect_identical(next_check$status, if (ambiguous) "indeterminate" else "metadata_changed")
    expect_identical(next_check$content_changed, NA)
  }
})

test_that("B1b retains HTTP ambiguity without a response and clears it on a new valid response", {
  cfg <- phase1_check_config()
  first <- b1b_observe(cfg, list(b1b_response(headers = list(ETag = "invalid",
    `Last-Modified` = "Tue, 01 Jan 2030 00:00:00 GMT"))), download = FALSE)
  b1b_persist(cfg, first, "ambiguous")
  previous <- b1b_last(cfg)$state_after$last_http_observation
  timeout <- function(req) stop(structure(list(message = "synthetic timeout", call = NULL),
    class = c("curl_error_operation_timedout", "curl_error", "error", "condition")))
  failed <- b1b_observe(cfg, rep(list(timeout), 3L), download = FALSE)
  expect_identical(failed$status, "source_unavailable")
  expect_false("last_http_invalid_validator" %in% failed$reason_codes)
  expect_identical(b1b_persist(cfg, failed, "timeout")$persistence$outcome, "committed")
  after <- b1b_last(cfg)$state_after
  b1b_equal(after$last_http_observation, previous)
  expect_true("last_http_invalid_validator" %in% after$last_check$reason_codes)
  fresh <- b1b_observe(cfg, list(b1b_response(headers = list(
    `Last-Modified` = "Wed, 02 Jan 2030 00:00:00 GMT"))), download = FALSE)
  expect_identical(fresh$metadata_changed, NA)
  expect_identical(b1b_persist(cfg, fresh, "fresh")$persistence$outcome, "committed")
  expect_false("last_http_invalid_validator" %in% b1b_last(cfg)$state_after$last_check$reason_codes)
  later <- b1b_observe(cfg, list(b1b_response(headers = list(
    `Last-Modified` = "Thu, 03 Jan 2030 00:00:00 GMT"))), download = FALSE)
  expect_true(later$metadata_changed)
})

test_that("B1b terminal ambiguity does not leak from retries or enable conditional reuse", {
  cfg <- phase1_check_config()
  first <- b1b_observe(cfg, list(b1b_response(503L, list(ETag = "invalid")),
    b1b_response(headers = list(`Last-Modified` = "Tue, 01 Jan 2030 00:00:00 GMT"))), download = FALSE)
  expect_true(any(vapply(first$transport$diagnostics, function(d) identical(d$code, "invalid_validator"), logical(1))))
  expect_false("last_http_invalid_validator" %in% first$reason_codes)
  expect_identical(b1b_persist(cfg, first)$persistence$outcome, "committed")
  next_check <- b1b_observe(cfg, list(b1b_response(headers = list(
    `Last-Modified` = "Wed, 02 Jan 2030 00:00:00 GMT"))), download = FALSE)
  expect_true(next_check$metadata_changed)
  for (headers in list(list(ETag = "invalid"), list(ETag = '"a"', etag = '"b"'))) {
    cfg <- phase1_check_config()
    headers[["Last-Modified"]] <- "Tue, 01 Jan 2030 00:00:00 GMT"
    accepted <- b1b_observe(cfg, list(b1b_response(headers = headers)))
    expect_identical(b1b_persist(cfg, accepted)$persistence$outcome, "committed")
    content <- b1b_last(cfg)$state_after$validated_content
    expect_null(content$etag_raw)
    expect_false(content$conditional_reuse_allowed)
    response <- function(req) {
      expect_false(any(c("If-None-Match", "If-Modified-Since") %in% names(req$headers)))
      b1b_response()(req)
    }
    observed <- b1b_observe(cfg, list(response))
    expect_identical(observed$status, "content_unchanged")
  }
})

test_that("B1b primary errors survive real lock cleanup failures before and after write", {
  for (point in c("before_temp_write", "after_rename")) local({
    # Retain unexplained synthetic lock artifacts throughout the test and retry.
    cfg <- list(data_dir = tempfile("synthetic-b1b-primary-"))
    obs <- b1b_observe(cfg); identity <- phase1_check_identity()
    artifact <- file.path(source_operational_root(cfg), "locks/demo.base.lock/unexpected.bin")
    bytes <- charToRaw("synthetic unexplained lock evidence")
    bug <- structure(list(message = "synthetic primary exception", call = NULL),
      class = c("b1b_primary_error", "error", "condition"))
    acquire <- acquire_source_lock; release <- release_source_lock
    held <- NULL; cleanup <- NULL; releases <- 0L; calls <- 0L; before <- NULL
    testthat::local_mocked_bindings(acquire_source_lock = function(...) {
      held <<- acquire(...); held
    }, release_source_lock = function(...) {
      releases <<- releases + 1L
      withCallingHandlers(release(...), source_state_block = function(e) cleanup <<- e)
    }, .package = "sampamaisrural")
    hooks <- stats::setNames(list(function(context) {
      calls <<- calls + 1L
      writeBin(bytes, artifact)
      before <<- b1b_files(cfg)
      stop(bug)
    }), point)
    observed <- tryCatch(b1b_persist(cfg, obs, "primary-check", hooks = hooks),
      b1b_primary_error = function(e) e)
    expect_identical(observed, bug)
    expect_s3_class(cleanup, "source_state_block")
    expect_identical(cleanup$code, "unexpected_lock_files")
    expect_identical(calls, 1L); expect_identical(releases, 1L)
    expect_identical(b1b_files(cfg), before)
    expect_identical(readBin(artifact, "raw", file.info(artifact)$size), bytes)
    expect_true(assert_source_lock(cfg, "demo.base", held))
    records <- read_source_revisions(cfg, identity)
    expect_length(records, if (point == "after_rename") 1L else 0L)

    # An unborrowed retry remains lock_busy; it must not run the body or clean up.
    busy <- local({
      testthat::local_mocked_bindings(source_persistence_prepare = function(...) stop(bug),
        .package = "sampamaisrural")
      b1b_persist(cfg, obs, "primary-check")
    })
    expect_identical(busy$status, "blocked")
    expect_identical(busy$persistence$outcome, "not_attempted")
    expect_identical(busy$persistence$error$code, "lock_busy")
    expect_true(busy$retryable)
    expect_identical(b1b_files(cfg), before)
    if (point == "after_rename") {
      expect_identical(records[[1L]]$record_sha256, source_record_checksum(records[[1L]]))
      # Reuse the retained owning lock explicitly; no artifact removal is needed.
      again <- b1b_persist(cfg, obs, "primary-check", lock = held, hooks = hooks)
      expect_identical(again$persistence$outcome, "committed")
      expect_identical(again$persistence$reason_codes, "already_committed")
      expect_identical(again$persistence$receipt, source_persistence_receipt(records[[1L]]))
      expect_length(read_source_revisions(cfg, identity), 1L)
      expect_identical(calls, 1L); expect_identical(releases, 1L)
      expect_identical(b1b_files(cfg), before)
      expect_true(assert_source_lock(cfg, "demo.base", held))
    }
  })
})

test_that("B1b release-only failure preserves a proved receipt and unexpected artifacts", {
  cfg <- list(data_dir = tempfile("synthetic-b1b-release-only-"))
  obs <- b1b_observe(cfg)
  artifact <- file.path(source_operational_root(cfg), "locks/demo.base.lock/unexpected.bin")
  bytes <- charToRaw("synthetic release-only lock evidence"); before <- NULL
  out <- b1b_persist(cfg, obs, "release-only", hooks = list(after_rename = function(context) {
    writeBin(bytes, artifact)
    before <<- b1b_files(cfg)
  }))
  expect_identical(out$status, "check_failed")
  expect_identical(out$persistence$outcome, "committed")
  expect_identical(out$persistence$error$code, "unexpected_lock_files")
  records <- read_source_revisions(cfg, phase1_check_identity())
  expect_length(records, 1L)
  expect_identical(out$persistence$receipt, source_persistence_receipt(records[[1L]]))
  expect_identical(b1b_files(cfg), before)
  expect_identical(readBin(artifact, "raw", file.info(artifact)$size), bytes)
})
