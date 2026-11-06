# Unit C fixtures are synthetic. No real socket, collection or scientific data.
c_bytes <- function(name) {
  path <- phase1_path(name)
  readBin(path, "raw", file.info(path)$size)
}
c_response <- function(status = 200L, bytes = raw(), headers = list(ETag = '"synthetic"')) {
  force(status); force(bytes); force(headers)
  function(req) httr2::response(status, req$url, method = req$method, headers = headers, body = bytes)
}
c_observe <- function(cfg, fmt = "json", status = 200L, bytes = c_bytes(paste0("report.", fmt)),
                      headers = list(ETag = '"synthetic"'), download = TRUE, responses = NULL,
                      identity = phase1_check_identity(fmt), registry = phase1_registry(), ...) {
  responses <- responses %||% list(c_response(status, bytes, headers)); count <- 0L
  source_observation_representation(cfg, identity, registry, allow_download = download,
    joint_acceptance_required = fmt %in% c("json", "csv") && identity$descriptor$source_id == "demo.base",
    execute = function(req, ...) {
      count <<- count + 1L
      if (count > length(responses)) stop("Unexpected synthetic coordination request")
      responses[[count]](req)
    }, clock = function() "2030-01-03T00:00:00Z", sleep = function(...) NULL, ...)
}
c_cycle <- function(cfg, check = "synthetic-cycle", observations = NULL, ...) {
  if (is.null(observations)) observations <- list(json = c_observe(cfg), csv = c_observe(cfg, "csv"))
  source_coordination_resolve(cfg, observations, check, phase1_registry(), "demo.base", ...)
}
c_persist <- function(cfg, cycle, ...) source_coordination_persist(cfg, cycle, clock = phase1_check_clock, ...)
c_records <- function(cfg, fmt = "json") read_source_revisions(cfg, phase1_check_identity(fmt))
c_last <- function(cfg, fmt = "json") tail(c_records(cfg, fmt), 1L)[[1L]]
c_equal <- function(a, b) expect_identical(source_canonical_json(a), source_canonical_json(b))
c_files <- function(cfg) {
  paths <- list.files(cfg$data_dir, recursive = TRUE, all.files = TRUE, full.names = TRUE)
  stats::setNames(vapply(paths, sha256_file, character(1)), paths)
}
c_forbid <- function(envir = parent.frame()) {
  forbidden <- c("source_http_request", "source_http_perform", "source_observation_representation",
    "store_source_content", "validate_source_pair", "reconcile_source_catalog", "collect_sampa_data", "prepare_equipment_data")
  bindings <- stats::setNames(lapply(forbidden, function(name) {
    force(name); function(...) stop(paste("C persistence forbidden", name))
  }), forbidden)
  do.call(testthat::local_mocked_bindings, c(bindings, list(.package = "sampamaisrural", .env = envir)))
}
c_seed <- function(cfg) c_persist(cfg, c_cycle(cfg, "seed"))

test_that("C persistence has no HTTP, pairing, catalog or sleep entry points", {
  ns <- asNamespace("sampamaisrural")
  names <- c("source_coordination_persist", "source_coordination_prepare", "source_coordination_result")
  calls <- unique(unlist(lapply(names, function(name) all.names(body(get(name, ns)), functions = TRUE))))
  expect_false(any(c("source_http_request", "source_coordination_observe", "source_observation_representation",
    "validate_source_pair", "reconcile_source_catalog", "Sys.sleep", "collect_sampa_data", "prepare_equipment_data") %in% calls))
  expect_false(any(grep("^source_coordination_", ls(ns), value = TRUE) %in% getNamespaceExports(ns)))
  expect_false(exists("sampa_check_updates", ns, inherits = FALSE))
})

test_that("C accepts a pair in one revision each with reciprocal logical evidence only", {
  cfg <- phase1_check_config(); cycle <- c_cycle(cfg); before <- c_files(cfg)
  c_forbid()
  out <- c_persist(cfg, cycle)
  expect_identical(out$status, "initialized"); expect_identical(out$content_changed, NA)
  expect_true(out$joint_acceptance$accepted); expect_true(out$joint_acceptance$baseline_confirmed)
  expect_identical(out$persistence$outcome, "committed")
  for (fmt in c("json", "csv")) {
    records <- c_records(cfg, fmt); expect_length(records, 1L)
    record <- records[[1L]]; p <- record$state_after$validated_content$validation$pair_evidence
    partner <- if (fmt == "json") "csv" else "json"
    expect_identical(record$event$type, "content_validated")
    expect_identical(p$check_id, cycle$check_id); expect_identical(p$representation, fmt)
    expect_identical(p$partner$representation, partner)
    expect_identical(p$content_sha256, cycle$observations[[fmt]]$content$sha256)
    expect_identical(p$partner$content_sha256, cycle$observations[[partner]]$content$sha256)
    expect_false(any(c("event_id", "state_revision", "record_sha256", "receipt") %in% names(p)))
    expect_false(any(c("event_id", "state_revision", "record_sha256", "receipt") %in% names(p$partner)))
    expect_identical(out$persistence$representations[[fmt]]$receipt, source_persistence_receipt(record))
    expect_null(record$state_after$last_confirmed_content_change)
    expect_false(grepl("Perfil sintético|Endereço sintético", source_canonical_json(record)))
    expect_identical(out$representations[[fmt]]$observation, cycle$observations[[fmt]])
  }
  expect_identical(c_files(cfg)[names(before)], before)
  expect_false(any(grepl("current.json|snapshot|processed|manifest", names(c_files(cfg)))))
  again <- c_persist(cfg, cycle)
  expect_identical(again$persistence$representations$json$receipt, out$persistence$representations$json$receipt)
  expect_length(c_records(cfg), 1L); expect_length(c_records(cfg, "csv"), 1L)
  expect_error(source_update_result("partial"), "invalid_status")
  expect_error(source_persistence_outcome("partial"), "invalid_persistence_outcome")
})

test_that("C preserves positive byte semantics including 304 and mixed responses", {
  cfg <- phase1_check_config(); c_seed(cfg)
  for (statuses in list(c(200L, 200L), c(304L, 304L), c(200L, 304L), c(304L, 200L))) {
    old <- lapply(c("json", "csv"), function(fmt) c_last(cfg, fmt)$state_after)
    observations <- list(json = c_observe(cfg, status = statuses[[1L]]), csv = c_observe(cfg, "csv", status = statuses[[2L]]))
    cycle <- c_cycle(cfg, paste0("check-", length(c_records(cfg))), observations)
    out <- c_persist(cfg, cycle)
    expect_identical(out$status, if (all(statuses == 200L)) "content_unchanged" else "not_modified")
    expect_identical(out$content_changed, if (all(statuses == 200L)) FALSE else NA)
    for (i in 1:2) if (statuses[[i]] == 304L) {
      new <- c_last(cfg, c("json", "csv")[[i]])$state_after
      fields <- c("sha256", "bytes", "relative_path", "retrieved_at")
      c_equal(new$validated_content[fields], old[[i]]$validated_content[fields])
      c_equal(new$latest_candidate, old[[i]]$latest_candidate)
    }
  }
  # JSON whitespace changes the byte hash without changing the projected pair.
  old <- c_last(cfg)$state_after$validated_content$sha256
  cycle <- c_cycle(cfg, "different", list(json = c_observe(cfg, bytes = c(c_bytes("report.json"), charToRaw("\n "))),
    csv = c_observe(cfg, "csv", status = 304L)))
  out <- c_persist(cfg, cycle)
  expect_identical(out$status, "content_changed"); expect_true(out$content_changed)
  expect_identical(c_last(cfg)$state_after$last_confirmed_content_change$previous_sha256, old)
  expect_true(c_last(cfg)$state_after$last_confirmed_content_change$candidate_accepted)
  expect_null(c_last(cfg, "csv")$state_after$last_confirmed_content_change)
})

test_that("C rejects mismatch and intrinsic failures without replacing validated history", {
  cases <- list(
    mismatch = list(json = "report.json", csv = "same-count-different.csv"),
    json_bad = list(json = "missing-required.json", csv = "report.csv"),
    csv_bad = list(json = "report.json", csv = NULL))
  for (case in cases) {
    cfg <- phase1_check_config(); c_seed(cfg)
    old <- lapply(c("json", "csv"), function(fmt) c_last(cfg, fmt)$state_after$validated_content)
    cycle <- c_cycle(cfg, "rejected", list(json = c_observe(cfg, bytes = c_bytes(case$json)),
      csv = c_observe(cfg, "csv", bytes = if (is.null(case$csv)) charToRaw("wrong;columns\na;b\n") else c_bytes(case$csv))))
    out <- c_persist(cfg, cycle)
    expect_identical(out$status, "incompatible_content"); expect_identical(out$content_changed, NA)
    expect_false(out$joint_acceptance$accepted)
    for (i in 1:2) {
      r <- c_last(cfg, c("json", "csv")[[i]])
      expect_identical(r$event$type, "candidate_stored")
      c_equal(r$state_after$validated_content, old[[i]])
      expect_null(r$state_after$last_confirmed_content_change)
    }
  }
})

test_that("C records incomplete cycles without unilateral acceptance", {
  for (missing in c("json", "csv")) {
    cfg <- phase1_check_config(); observations <- list(json = c_observe(cfg), csv = c_observe(cfg, "csv"))
    observations[missing] <- list(NULL)
    out <- c_persist(cfg, c_cycle(cfg, observations = observations))
    expect_identical(out$status, "indeterminate"); expect_identical(out$content_changed, NA)
    expect_false(out$joint_acceptance$accepted)
    present <- setdiff(c("json", "csv"), missing)
    expect_identical(c_last(cfg, present)$event$type, "candidate_stored")
    expect_null(c_last(cfg, present)$state_after$validated_content); expect_length(c_records(cfg, missing), 0L)
  }
  cfg <- phase1_check_config(); c_seed(cfg); old <- c_last(cfg)$state_after
  out <- c_persist(cfg, c_cycle(cfg, "missing-304", list(json = c_observe(cfg, status = 304L), csv = NULL)))
  expect_identical(out$status, "indeterminate")
  expect_identical(c_last(cfg)$event$type, "check_finished")
  c_equal(c_last(cfg)$state_after$validated_content, old$validated_content)
  c_equal(c_last(cfg)$state_after$latest_candidate, old$latest_candidate)
})

test_that("C uses the actual projection helper and does not promote partial comparison", {
  cfg <- phase1_check_config()
  json <- phase1_json(); json$partners <- lapply(json$partners, function(r) { r$Extra <- list(nested = 1); r })
  csv <- read_source_payload(phase1_path("report.csv"), "csv"); csv$Extra <- "synthetic unsupported projection"
  path <- withr::local_tempfile(fileext = ".csv"); readr::write_delim(csv, path, delim = ";")
  observations <- list(json = c_observe(cfg, bytes = charToRaw(as.character(jsonlite::toJSON(json, auto_unbox = TRUE, null = "null")))),
    csv = c_observe(cfg, "csv", bytes = readBin(path, "raw", file.info(path)$size)))
  cycle <- c_cycle(cfg, observations = observations)
  expect_identical(cycle$pair$classification, "insufficient_evidence"); expect_identical(cycle$pair$decision, "warn")
  out <- c_persist(cfg, cycle)
  expect_identical(out$status, "indeterminate"); expect_identical(out$content_changed, NA)
  for (fmt in c("json", "csv")) {
    expect_null(c_last(cfg, fmt)$state_after$validated_content)
    expect_identical(c_last(cfg, fmt)$state_after$latest_candidate$validation$pair_evidence$classification, "insufficient_evidence")
  }
  # Empty permitted records still have a consistent declared projection.
  cfg <- phase1_check_config()
  out <- c_persist(cfg, c_cycle(cfg, observations = list(json = c_observe(cfg, bytes = c_bytes("empty.json")),
    csv = c_observe(cfg, "csv", bytes = c_bytes("empty.csv")))))
  expect_true(out$joint_acceptance$accepted)
})

test_that("C known HTTP failures and HEAD preserve pending/history semantics", {
  for (status in c(404L, 503L)) {
    cfg <- phase1_check_config()
    failures <- rep(list(c_response(status)), if (status == 503L) 3L else 1L)
    cycle <- c_cycle(cfg, observations = list(json = c_observe(cfg), csv = c_observe(cfg, "csv", responses = failures)))
    out <- c_persist(cfg, cycle)
    expect_identical(out$status, "source_unavailable"); expect_identical(out$content_changed, NA)
    expect_identical(out$retryable, status == 503L)
    expect_identical(c_last(cfg)$event$type, "candidate_stored")
    expect_identical(c_last(cfg, "csv")$event$type, "check_finished")
    expect_null(c_last(cfg)$state_after$validated_content)
  }
  cfg <- phase1_check_config()
  for (i in 1:3) {
    headers <- if (i < 3) list(ETag = '"head"') else list(ETag = '"changed"')
    obs <- list(json = c_observe(cfg, download = FALSE, headers = headers), csv = c_observe(cfg, "csv", download = FALSE, headers = headers))
    out <- c_persist(cfg, c_cycle(cfg, paste0("head-", i), obs))
    expect_identical(out$status, if (i == 3L) "metadata_changed" else "indeterminate")
    expect_identical(out$content_changed, NA); expect_null(out$pair)
    for (fmt in c("json", "csv")) {
      expect_identical(c_last(cfg, fmt)$event$type, "check_finished")
      expect_identical(obs[[fmt]]$transport$method, "HEAD")
    }
  }
})

test_that("C validates both generations and all referenced blobs before any commit", {
  for (stale in list("json", "csv", c("json", "csv"))) {
    cfg <- phase1_check_config(); original <- c_cycle(cfg)
    c_seed(cfg)
    # Use absence on only the non-stale side to exercise both asymmetric cases.
    fresh <- c_cycle(cfg, "new")
    fresh$observations[stale] <- original$observations[stale]
    # Rebuild evidence with the selected original observations.
    cycle <- c_cycle(cfg, "stale", fresh$observations)
    before <- c_files(cfg); out <- c_persist(cfg, cycle)
    expect_identical(out$status, "blocked"); expect_true("stale_state_revision" %in% out$reason_codes)
    expect_identical(out$persistence$outcome, "not_attempted"); expect_identical(c_files(cfg), before)
  }
  cfg <- phase1_check_config(); cycle <- c_cycle(cfg)
  path <- source_safe_path(source_operational_root(cfg), cycle$observations$csv$content$relative_path)
  # Deliberate corruption of an isolated synthetic blob, not cleanup.
  writeBin(charToRaw("synthetic corrupt bytes"), path)
  out <- c_persist(cfg, cycle)
  expect_identical(out$status, "blocked")
  expect_length(c_records(cfg), 0L); expect_length(c_records(cfg, "csv"), 0L)
})

test_that("C shares one source lock, prepares both first, and never releases borrowed ownership", {
  cfg <- phase1_check_config(); cycle <- c_cycle(cfg)
  held <- acquire_source_lock(cfg, "demo.base"); prepared <- character()
  prepare <- source_persistence_prepare
  testthat::local_mocked_bindings(acquire_source_lock = function(...) stop("nested lock"),
    source_persistence_prepare = function(config, observation, check_id, lock, resolution = NULL) {
      expect_true(assert_source_lock(config, "demo.base", lock))
      prepared <<- c(prepared, observation$context$effective_identity$descriptor$representation)
      prepare(config, observation, check_id, lock, resolution)
    }, .package = "sampamaisrural")
  out <- local({
    testthat::local_mocked_bindings(release_source_lock = function(...) stop("borrowed release"), .package = "sampamaisrural")
    c_forbid()
    c_persist(cfg, cycle, lock = held, hooks = list(json = list(before_temp_write = function(context) {
      expect_identical(prepared, c("json", "csv"))
    })))
  })
  expect_identical(out$persistence$outcome, "committed"); expect_true(assert_source_lock(cfg, "demo.base", held))
  expect_true(release_source_lock(cfg, held))
})

test_that("C partial writes retain immutable evidence and replay only the missing partner", {
  for (first in c("json", "csv")) {
    cfg <- phase1_check_config(); cycle <- c_cycle(cfg)
    # Also exercise a preexisting CSV-only commit using the shared primitive.
    if (first == "csv") with_source_lock(cfg, "demo.base", function(held) {
      p <- source_persistence_prepare(cfg, source_coordination_terminal(cycle, "csv"), cycle$check_id, held, cycle)
      source_persistence_commit(cfg, p, held)
    })
    failing <- if (first == "json") "csv" else "json"
    hooks <- stats::setNames(list(list(before_temp_write = function(context) source_state_block("synthetic_write_failure"))), failing)
    out <- c_persist(cfg, cycle, hooks = hooks)
    expect_identical(out$status, "check_failed"); expect_identical(out$persistence$outcome, "partial")
    expect_identical(out$persistence$representations[[first]]$outcome, "committed")
    expect_null(out$persistence$representations[[failing]]$receipt)
    original <- c_records(cfg, first)[[1L]]
    expect_false(out$joint_acceptance$baseline_confirmed)
    replay <- c_persist(cfg, cycle)
    expect_identical(replay$persistence$outcome, "committed")
    expect_identical(c_records(cfg, first)[[1L]], original)
    expect_identical(replay$persistence$representations[[first]]$receipt, source_persistence_receipt(original))
    expect_length(c_records(cfg), 1L); expect_length(c_records(cfg, "csv"), 1L)
    expect_identical(c_persist(cfg, cycle)$persistence$outcome, "committed")
  }
})

test_that("C reconciles uncertain second writes and never duplicates a proved commit", {
  cfg <- phase1_check_config(); cycle <- c_cycle(cfg)
  reconcile <- source_persistence_reconcile
  out <- local({
    testthat::local_mocked_bindings(source_persistence_reconcile = function(config, prepared, lock) {
      if (prepared$identity$descriptor$representation == "csv") return(source_persistence_outcome("uncertain", error = "synthetic_unreadable"))
      reconcile(config, prepared, lock)
    }, .package = "sampamaisrural")
    c_persist(cfg, cycle)
  })
  expect_identical(out$persistence$outcome, "partial"); expect_identical(out$status, "check_failed")
  expect_null(out$persistence$representations$csv$receipt)
  expect_length(c_records(cfg, "csv"), 1L)
  again <- c_persist(cfg, cycle)
  expect_identical(again$persistence$outcome, "committed")
  expect_length(c_records(cfg), 1L); expect_length(c_records(cfg, "csv"), 1L)
  # Same token with new times/generations cannot create another terminal event.
  collision <- c_cycle(cfg, cycle$check_id)
  result <- c_persist(cfg, collision)
  expect_identical(result$status, "blocked"); expect_true("check_id_conflict" %in% result$reason_codes)
})

test_that("C refuses completing a partial cycle after the committed side advanced", {
  cfg <- phase1_check_config(); cycle <- c_cycle(cfg)
  c_persist(cfg, cycle, hooks = list(csv = list(before_temp_write = function(context) source_state_block("synthetic_failure"))))
  next_cycle <- c_cycle(cfg, "later", list(json = c_observe(cfg, download = FALSE), csv = NULL))
  c_persist(cfg, next_cycle)
  out <- c_persist(cfg, cycle)
  expect_identical(out$status, "check_failed"); expect_identical(out$persistence$outcome, "partial")
  expect_identical(out$persistence$representations$json$receipt$check_id, cycle$check_id)
  expect_length(c_records(cfg), 2L); expect_length(c_records(cfg, "csv"), 0L)
})

test_that("C prior partial or incompatible check IDs are not a logical baseline", {
  cfg <- phase1_check_config(); cycle <- c_cycle(cfg)
  c_persist(cfg, cycle, hooks = list(csv = list(before_temp_write = function(context) source_state_block("synthetic_failure"))))
  new <- c_cycle(cfg, "new-cycle")
  expect_identical(c_persist(cfg, new)$status, "initialized")
  # An independently accepted JSON no longer carries reciprocal pair evidence.
  obs <- c_observe(cfg); obs$joint_acceptance_required <- FALSE
  obs <- source_coordination_terminal(new, "json")
  obs$context$state_revision <- c_last(cfg)$state_revision
  obs$baseline <- list(identity_sha256 = phase1_check_identity()$sha256, sha256 = obs$content$sha256)
  obs$status <- "content_unchanged"; obs$content_changed <- FALSE; obs$joint_acceptance_required <- FALSE
  obs$validation$pair_evidence <- NULL
  source_persistence_representation(cfg, obs, "standalone", clock = phase1_check_clock)
  expect_identical(c_persist(cfg, c_cycle(cfg, "rejoin"))$status, "initialized")
})

test_that("C unexpected primary errors survive cleanup and explicit retry uses the existing revision", {
  # Deliberately retain unexplained lock artifacts, including after the test.
  cfg <- list(data_dir = tempfile("synthetic-c-primary-")); cycle <- c_cycle(cfg)
  bug <- structure(list(message = "synthetic primary", call = NULL), class = c("c_primary", "error", "condition"))
  held <- NULL; acquire <- acquire_source_lock
  artifact <- file.path(source_operational_root(cfg), "locks/demo.base.lock/unexpected.bin")
  testthat::local_mocked_bindings(acquire_source_lock = function(...) { held <<- acquire(...); held }, .package = "sampamaisrural")
  hooks <- list(json = list(after_rename = function(context) { writeBin(charToRaw("synthetic artifact"), artifact); stop(bug) }))
  observed <- tryCatch(c_persist(cfg, cycle, hooks = hooks), c_primary = function(e) e)
  expect_identical(observed, bug); expect_length(c_records(cfg), 1L); expect_length(c_records(cfg, "csv"), 0L)
  before <- readBin(artifact, "raw", file.info(artifact)$size)
  busy <- c_persist(cfg, cycle)
  expect_identical(busy$status, "blocked"); expect_true("lock_busy" %in% busy$reason_codes)
  replay <- c_persist(cfg, cycle, lock = held)
  expect_identical(replay$persistence$outcome, "committed")
  expect_length(c_records(cfg), 1L); expect_length(c_records(cfg, "csv"), 1L)
  expect_identical(readBin(artifact, "raw", file.info(artifact)$size), before)
  expect_true(assert_source_lock(cfg, "demo.base", held))
})

test_that("C release-only failures preserve committed receipts", {
  cfg <- list(data_dir = tempfile("synthetic-c-cleanup-")); cycle <- c_cycle(cfg)
  artifact <- file.path(source_operational_root(cfg), "locks/demo.base.lock/unexpected.bin")
  out <- c_persist(cfg, cycle, hooks = list(csv = list(after_rename = function(context) writeBin(charToRaw("synthetic"), artifact))))
  expect_identical(out$status, "check_failed"); expect_identical(out$persistence$outcome, "committed")
  expect_true(out$joint_acceptance$baseline_confirmed)
  for (fmt in c("json", "csv")) expect_identical(out$persistence$representations[[fmt]]$receipt, source_persistence_receipt(c_last(cfg, fmt)))
  expect_true(file.exists(artifact))
})

c_catalog_registry <- function() {
  registry <- phase1_registry()
  registry$sources <- c(registry$sources, list(list(source_id = "demo.catalog", catalog_slug = NULL,
    name = "Synthetic catalog", role = "catalog", enabled = TRUE, overlaps_with = list(),
    representations = list(json = list(parser = "sampa_catalog_json_v1", contract = "catalog-v1.yml", filename = "catalog.json",
      endpoint_config = "catalog_url", default_url = "https://example.invalid/catalog")))))
  registry
}
c_catalog <- function(cfg, payload = NULL, check = "catalog", status = 200L, registry = c_catalog_registry(), download = TRUE) {
  if (is.null(payload)) payload <- lapply(registry$sources[1:2], function(s) list(name = "Synthetic name",
    json = paste0("https://example.invalid/reports/", s$catalog_slug, ".json"),
    csv = paste0("https://example.invalid/reports/", s$catalog_slug, ".csv")))
  identity <- source_request_identity("demo.catalog", "json", "https://example.invalid/catalog", registry)
  obs <- c_observe(cfg, identity = identity, registry = registry, status = status, download = download,
    bytes = charToRaw(as.character(jsonlite::toJSON(payload, auto_unbox = TRUE))))
  source_coordination_catalog(cfg, obs, check, registry)
}

test_that("C catalog review allows only registered mappings; aggregate block stops every report", {
  registry <- c_catalog_registry(); cfg <- phase1_check_config(); good <- c_catalog(cfg)
  expect_identical(good$coverage$decision, "allow")
  expect_identical(c_persist(cfg, good)$persistence$outcome, "committed")
  path <- source_safe_path(source_operational_root(cfg), good$observations$json$content$relative_path)
  payload <- read_source_payload(path, "json")
  unknown <- c(payload, list(list(name = "Synthetic additional", json = "https://example.invalid/new.json", csv = "https://example.invalid/new.csv")))
  review <- c_catalog(cfg, unknown, "review")
  expect_identical(review$coverage$decision, "review"); expect_identical(nrow(review$coverage$mapping), 4L)
  expect_identical(c_persist(cfg, review)$persistence$outcome, "committed")
  requests <- 0L
  out <- source_coordination_observe(cfg, "demo.base", review, "report", registry, allow_download = TRUE,
    execute = function(req, ...) {
      requests <<- requests + 1L
      c_response(bytes = c_bytes(if (endsWith(req$url, ".csv")) "report.csv" else "report.json"))(req)
    }, clock = phase1_check_clock, sleep = function(...) NULL)
  expect_equal(requests, 2L); expect_true(source_coordination_accepted(out))
  expect_error(source_coordination_observe(cfg, "unknown.source", review, "unknown", registry), "unknown_coordination_source")
  invalid_url <- payload; invalid_url[[2]]$csv <- "https://elsewhere.invalid/subset.csv"
  mismatch <- payload; mismatch[[2]]$csv <- payload[[1]]$csv
  for (bad in list(payload[1], c(payload, payload[1]), invalid_url, mismatch)) {
    blocked <- c_catalog(cfg, bad, paste0("bad-", length(read_source_revisions(cfg, good$observations$json$context$effective_identity))))
    expect_identical(blocked$coverage$decision, "block"); expect_equal(nrow(blocked$coverage$mapping), 0L)
    no_requests <- source_coordination_observe(cfg, "demo.base", blocked, "blocked-report", registry,
      execute = function(...) stop("Forbidden unaffected subset request"))
    result <- c_persist(cfg, no_requests)
    expect_identical(result$status, "blocked"); expect_identical(result$persistence$outcome, "not_attempted")
    previous <- read_source_state(cfg, good$observations$json$context$effective_identity)$validated_content
    result <- c_persist(cfg, blocked)
    expect_identical(result$status, "incompatible_content")
    records <- read_source_revisions(cfg, good$observations$json$context$effective_identity)
    expect_identical(tail(records, 1)[[1]]$event$type, "candidate_stored")
    c_equal(tail(records, 1)[[1]]$state_after$validated_content, previous)
  }
  head <- c_catalog(cfg, check = "head", download = FALSE)
  expect_null(head$coverage)
  empty <- source_coordination_observe(cfg, "demo.base", head, "head-report", registry,
    execute = function(...) stop("Forbidden GET fallback"))
  expect_identical(c_persist(cfg, empty)$status, "indeterminate")
})

test_that("C catalog 304 under new coverage preserves historical validated content", {
  cfg <- phase1_check_config(); old <- c_catalog(cfg); c_persist(cfg, old)
  registry <- c_catalog_registry()
  extra <- registry$sources[[2]]; extra$source_id <- "demo.new"; extra$catalog_slug <- "new-registered"
  for (fmt in c("json", "csv")) extra$representations[[fmt]]$filename <- paste0(extra$catalog_slug, ".", fmt)
  registry$sources <- c(registry$sources, list(extra)); registry$registry_revision <- "synthetic-2"
  now <- c_catalog(cfg, check = "coverage-now", status = 304L, registry = registry)
  expect_identical(now$coverage$decision, "block")
  before <- read_source_state(cfg, now$observations$json$context$effective_identity)
  out <- c_persist(cfg, now)
  expect_identical(out$status, "incompatible_content")
  r <- tail(read_source_revisions(cfg, now$observations$json$context$effective_identity), 1L)[[1L]]
  expect_identical(r$event$type, "state_validation_failed")
  c_equal(r$state_after$validated_content, before$validated_content)
  c_equal(r$state_after$latest_candidate, before$latest_candidate)
})

test_that("C metadata round-trip preserves invalid validator ambiguity", {
  dates <- c("Tue, 01 Jan 2030 00:00:00 GMT", "Wed, 02 Jan 2030 00:00:00 GMT")
  cases <- list(invalid = list(ETag = "invalid"), duplicate = list(ETag = '"a"', etag = '"b"'),
    absent = list(), valid = list(ETag = '"same"'))
  for (name in names(cases)) {
    cfg <- phase1_check_config()
    first <- c_observe(cfg, download = FALSE, headers = c(cases[[name]], list(`Last-Modified` = dates[[1L]])))
    cycle <- c_cycle(cfg, "head-before", list(json = first))
    out <- c_persist(cfg, cycle)
    expect_identical(out$persistence$representations$json$outcome, "committed")
    ambiguous <- name %in% c("invalid", "duplicate")
    expect_identical("last_http_invalid_validator" %in% c_last(cfg)$state_after$last_check$reason_codes, ambiguous)
    next_headers <- c(if (name == "valid") cases[[name]] else list(), list(`Last-Modified` = dates[[2L]]))
    next_obs <- c_observe(cfg, download = FALSE, headers = next_headers)
    expect_identical(next_obs$metadata_changed, if (ambiguous) NA else TRUE)
    expect_null(c_last(cfg)$state_after$validated_content)
  }
  cfg <- phase1_check_config()
  observations <- list(json = c_observe(cfg, headers = list(ETag = '"a"', etag = '"b"', `Last-Modified` = dates[[1]])),
    csv = c_observe(cfg, "csv"))
  c_persist(cfg, c_cycle(cfg, observations = observations))
  expect_false(c_last(cfg)$state_after$validated_content$conditional_reuse_allowed)
  c_observe(cfg, responses = list(function(req) {
    expect_false(any(tolower(names(req$headers)) %in% c("if-none-match", "if-modified-since")))
    c_response(200L, c_bytes("report.json"))(req)
  }))
})

test_that("C preserves failed historical validation and pending 304 history", {
  cfg <- phase1_check_config(); c_seed(cfg)
  old <- c_last(cfg)$state_after
  strict <- phase1_contract(); strict$version <- 2L; strict$schema$properties$partners$min_items <- 100L
  observations <- list(json = c_observe(cfg, status = 304L, contract_loader = function(...) strict),
    csv = c_observe(cfg, "csv", contract_loader = function(...) strict))
  cycle <- c_cycle(cfg, "strict", observations, contract_loader = function(...) strict)
  out <- c_persist(cfg, cycle)
  expect_identical(out$status, "incompatible_content"); expect_false(out$joint_acceptance$accepted)
  expect_identical(c_last(cfg)$event$type, "state_validation_failed")
  for (field in c("validated_content", "latest_candidate", "last_confirmed_content_change")) {
    c_equal(c_last(cfg)$state_after[[field]], old[[field]])
  }
  expect_identical(c_last(cfg, "csv")$event$type, "candidate_stored")
  cycle <- c_cycle(cfg, "mismatch-304", list(json = c_observe(cfg, status = 304L),
    csv = c_observe(cfg, "csv", bytes = c_bytes("same-count-different.csv"))))
  out <- c_persist(cfg, cycle)
  expect_identical(out$status, "incompatible_content")
  expect_identical(c_last(cfg)$event$type, "check_finished")
  c_equal(c_last(cfg)$state_after$validated_content, old$validated_content)
})

test_that("C preserves typed operational failures and unexpected programming errors", {
  fail <- function(class) function(req) stop(structure(list(message = "SYNTHETIC SECRET", call = NULL),
    class = c(class, "curl_error", "error", "condition")))
  for (kind in c("timeout", "tls", "protocol")) {
    cfg <- phase1_check_config()
    responses <- switch(kind, timeout = rep(list(fail("curl_error_operation_timedout")), 3L),
      tls = list(fail("curl_error_peer_failed_verification")), protocol = list(c_response(206L)))
    observations <- list(json = c_observe(cfg), csv = c_observe(cfg, "csv", responses = responses))
    out <- c_persist(cfg, c_cycle(cfg, observations = observations))
    expect_identical(out$status, if (kind == "timeout") "source_unavailable" else "check_failed")
    expect_identical(c_last(cfg)$event$type, "candidate_stored")
    expect_identical(c_last(cfg, "csv")$event$type, "check_finished")
    expect_null(c_last(cfg, "csv")$state_after$validated_content)
    expect_false(grepl("SYNTHETIC SECRET", source_canonical_json(c_last(cfg, "csv")), fixed = TRUE))
    expect_identical(observations$csv$retryable, kind == "timeout")
  }
  cfg <- phase1_check_config()
  expect_error(c_cycle(cfg, pair_validator = function(...) stop("synthetic pair bug")), "synthetic pair bug")
  expect_length(c_records(cfg), 0L)
  cycle <- c_cycle(cfg)
  expect_error(c_persist(cfg, cycle, hooks = list(json = list(before_temp_write = function(...) stop("synthetic prewrite bug")))),
    "synthetic prewrite bug")
  expect_length(c_records(cfg), 0L); expect_length(c_records(cfg, "csv"), 0L)
})

test_that("C confirms both prepared heads again and detects corrupt chains", {
  cfg <- phase1_check_config(); cycle <- c_cycle(cfg); prepare <- source_persistence_prepare
  out <- local({
    testthat::local_mocked_bindings(source_persistence_prepare = function(config, observation, check_id, lock, resolution = NULL) {
      p <- prepare(config, observation, check_id, lock, resolution)
      if (observation$context$effective_identity$descriptor$representation == "csv") {
        identity <- phase1_check_identity("csv")
        phase1_check_commit(config, identity, new_source_state(identity), lock = lock)
      }
      p
    }, .package = "sampamaisrural")
    c_persist(cfg, cycle)
  })
  expect_identical(out$status, "blocked"); expect_true("stale_state_revision" %in% out$reason_codes)
  expect_length(c_records(cfg), 0L); expect_length(c_records(cfg, "csv"), 1L)
  fresh <- c_cycle(cfg, "fresh")
  writeLines("synthetic corrupted revision", phase1_check_revision(cfg, phase1_check_identity("csv")))
  before <- c_files(cfg); blocked <- c_persist(cfg, fresh)
  expect_identical(blocked$status, "blocked"); expect_identical(blocked$persistence$outcome, "not_attempted")
  expect_identical(c_files(cfg), before)
})

test_that("C binds pair evidence to the actual identities and content compared", {
  cfg <- phase1_check_config(); cycle <- c_cycle(cfg)
  changed <- cycle
  changed$observations$json <- c_observe(cfg, bytes = c(c_bytes("report.json"), charToRaw("\n")))
  expect_error(c_persist(cfg, changed), "invalid_joint_evidence")
  changed <- cycle; changed$pair$partner$effective_identity_sha256 <- strrep("a", 64L)
  expect_error(c_persist(cfg, changed), "invalid_joint_evidence")
  changed <- cycle; changed$pair$state_revision <- 1L
  expect_error(c_persist(cfg, changed), class = "source_update_argument_error")
  expect_length(c_records(cfg), 0L); expect_length(c_records(cfg, "csv"), 0L)
})

test_that("C accepts a consistent pair while preserving a JSON schema warning", {
  cfg <- phase1_check_config(); json <- phase1_json()
  # The contract allows numeric strings but explicitly prefers numeric values.
  json$partners <- lapply(json$partners, function(row) { row$Longitude <- as.character(row$Longitude); row })
  obs <- c_observe(cfg, bytes = charToRaw(as.character(jsonlite::toJSON(json, auto_unbox = TRUE, null = "null"))))
  expect_identical(obs$validation$decision, "warn")
  cycle <- c_cycle(cfg, observations = list(json = obs, csv = c_observe(cfg, "csv")))
  expect_identical(cycle$pair$classification, "consistent_under_projection")
  expect_identical(cycle$pair$decision, "warn")
  out <- c_persist(cfg, cycle)
  expect_true(out$joint_acceptance$accepted); expect_identical(out$severity, "warning")
  for (fmt in c("json", "csv")) expect_identical(c_last(cfg, fmt)$event$type, "content_validated")
})

test_that("C redirect evidence and persistence stay with terminal identities", {
  cfg <- phase1_check_config(); c_seed(cfg)
  original <- c_last(cfg); target <- phase1_check_identity(query = "?synthetic-target=1")
  obs <- c_observe(cfg, responses = list(c_response(302L, headers = list(Location = target$descriptor$absolute_request_url)),
    function(req) {
      expect_false(any(tolower(names(req$headers)) %in% c("if-none-match", "if-modified-since")))
      c_response(200L, c_bytes("report.json"))(req)
    }))
  cycle <- c_cycle(cfg, "redirect", list(json = obs, csv = c_observe(cfg, "csv")))
  out <- c_persist(cfg, cycle)
  expect_identical(out$status, "initialized"); expect_true(out$representations$json$observation$redirected)
  expect_null(obs$baseline); expect_identical(c_last(cfg), original)
  records <- read_source_revisions(cfg, target)
  expect_length(records, 1L); expect_identical(records[[1]]$event$type, "content_validated")
  p <- records[[1]]$state_after$validated_content$validation$pair_evidence
  expect_identical(p$requested_identity_sha256, phase1_check_identity()$sha256)
  expect_identical(p$effective_identity_sha256, target$sha256)
})
