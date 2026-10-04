test_that("1B I reads are pure and revisions are immutable, monotonic and reproducible", {
  cfg <- phase1_check_config(); identity <- phase1_check_identity()
  expect_null(read_source_state(cfg, identity))
  expect_false(dir.exists(cfg$data_dir))
  state <- new_source_state(identity, "synthetic-1")
  expect_true(validate_source_state(state, identity))
  state <- phase1_check_commit(cfg, identity, state)
  first <- phase1_check_revision(cfg, identity)
  bytes <- readBin(first, "raw", n = file.info(first)$size)
  expect_equal(state$state_revision, 1)
  state <- phase1_check_commit(cfg, identity, state, 2)
  expect_equal(state$state_revision, 2)
  expect_identical(source_canonical_json(state), source_canonical_json(read_source_state(cfg, identity)))
  records <- read_source_revisions(cfg, identity)
  expect_length(records, 2)
  expect_null(records[[1]]$previous_record_sha256)
  expect_identical(records[[2]]$previous_record_sha256, records[[1]]$record_sha256)
  for (record in records) {
    expect_identical(record$record_sha256, source_record_checksum(record))
    expect_identical(record$record_sha256, source_record_checksum(rev(record)))
  }
  expect_identical(bytes, readBin(first, "raw", n = length(bytes)))
  expect_false(file.exists(file.path(dirname(first), "current.json")))
  expect_error(phase1_check_commit(cfg, identity, new_source_state(identity), 3), "stale_state_revision")
  expect_error(phase1_check_commit(cfg, identity, state, 2), "duplicate_event_id")
  expect_false(dir.exists(file.path(cfg$data_dir, "raw")))
  expect_false(dir.exists(file.path(cfg$data_dir, "processed")))
})

test_that("1B I corrupt or discontinuous chains block instead of falling back", {
  mutations <- list(
    invalid_json = function(path) writeLines("{partial", path),
    checksum = function(path) phase1_check_rewrite(path, function(r) {r$event$code <- "changed"; r}, FALSE),
    previous = function(path) phase1_check_rewrite(path, function(r) {r$previous_record_sha256 <- paste(rep("a", 64), collapse = ""); r}),
    duplicate_revision = function(path) phase1_check_rewrite(path, function(r) {r$state_revision <- 1L; r}),
    state_revision = function(path) phase1_check_rewrite(path, function(r) {r$state_after$state_revision <- 99L; r}),
    schema_version = function(path) phase1_check_rewrite(path, function(r) {r$state_after$state_schema_version <- 2L; r}),
    record_version = function(path) phase1_check_rewrite(path, function(r) {r$record_schema_version <- 2L; r}),
    source_id = function(path) phase1_check_rewrite(path, function(r) {r$state_after$source_id <- "demo.subset"; r}),
    representation = function(path) phase1_check_rewrite(path, function(r) {r$state_after$representation <- "csv"; r}),
    identity = function(path) phase1_check_rewrite(path, function(r) {r$state_after$request_identity <- phase1_check_identity(query = "?new=1"); r}),
    missing_field = function(path) phase1_check_rewrite(path, function(r) {r$state_after$last_error <- NULL; r$state_after <- r$state_after[!names(r$state_after) %in% "last_error"]; r}))
  for (name in names(mutations)) {
    cfg <- phase1_check_config(); identity <- phase1_check_identity()
    state <- phase1_check_commit(cfg, identity, new_source_state(identity))
    phase1_check_commit(cfg, identity, state, 2)
    path <- phase1_check_revision(cfg, identity, 2)
    mutations[[name]](path)
    before <- sha256_file(path)
    expect_error(read_source_state(cfg, identity), "BLOCK", info = name)
    expect_error(phase1_check_commit(cfg, identity, state, 3), "BLOCK", info = name)
    expect_identical(sha256_file(path), before, info = name)
  }
  cfg <- phase1_check_config(); identity <- phase1_check_identity()
  state <- phase1_check_commit(cfg, identity, new_source_state(identity))
  state <- phase1_check_commit(cfg, identity, state, 2)
  phase1_check_commit(cfg, identity, state, 3)
  # Remove only an isolated synthetic revision to inject a missing sequence.
  unlink(phase1_check_revision(cfg, identity, 2))
  expect_error(read_source_state(cfg, identity), "revision_gap")
  cfg <- phase1_check_config()
  phase1_check_commit(cfg, identity, new_source_state(identity))
  file.copy(phase1_check_revision(cfg, identity), paste0(phase1_check_revision(cfg, identity), ".copy"))
  expect_error(read_source_state(cfg, identity), "invalid_revision_filename")
})

test_that("1B I locks require ownership and never clear unknown or orphan locks", {
  cfg <- phase1_check_config()
  lock <- acquire_source_lock(cfg, "demo.base", phase1_check_clock, function() "synthetic-owner")
  expect_identical(lock$owner$token, "synthetic-owner")
  expect_equal(lock$owner$pid, Sys.getpid())
  expect_identical(lock$owner$started_at, phase1_check_clock())
  expect_true(assert_source_lock(cfg, "demo.base", lock))
  expect_error(acquire_source_lock(cfg, "demo.base"), "lock_busy")
  wrong <- lock; wrong$owner$token <- "wrong-owner"
  expect_error(release_source_lock(cfg, wrong), "lock_not_owned")
  expect_true(assert_source_lock(cfg, "demo.base", lock))
  other <- acquire_source_lock(cfg, "demo.subset")
  expect_true(release_source_lock(cfg, other))
  expect_error(assert_source_lock(cfg, "demo.subset", lock), "lock_identity_mismatch")
  expect_true(release_source_lock(cfg, lock))
  expect_false(dir.exists(source_safe_path(lock$root, "locks/demo.base.lock")))
  for (kind in c("missing", "corrupt", "orphan")) {
    cfg <- phase1_check_config()
    path <- source_ensure_directory(source_operational_root(cfg), "locks/demo.base.lock")
    if (kind == "corrupt") writeLines("{partial", file.path(path, "owner.json"))
    if (kind == "orphan") source_write_json(list(token = "orphan", pid = 999999L, hostname = "other-host",
      started_at = "2000-01-01T00:00:00Z"), file.path(path, "owner.json"))
    expect_error(acquire_source_lock(cfg, "demo.base"), "lock_busy", info = kind)
    expect_true(dir.exists(path), info = kind)
    fake <- list(root = source_operational_root(cfg), source_id = "demo.base", owner = lock$owner)
    expect_error(release_source_lock(cfg, fake), "BLOCK", info = kind)
    expect_true(dir.exists(path), info = kind)
  }
})

test_that("1B I atomic revisions survive injected failures without overwriting", {
  for (point in c("before_temp_write", "after_temp_write", "before_rename", "after_rename")) {
    cfg <- phase1_check_config(); identity <- phase1_check_identity()
    state <- phase1_check_commit(cfg, identity, new_source_state(identity))
    first_hash <- sha256_file(phase1_check_revision(cfg, identity))
    hooks <- stats::setNames(list(function(context) stop("synthetic failure")), point)
    expect_error(phase1_check_commit(cfg, identity, state, 2, hooks = hooks), "synthetic failure", info = point)
    latest <- read_source_state(cfg, identity)
    expect_equal(latest$state_revision, if (point == "after_rename") 2 else 1, info = point)
    expect_identical(first_hash, sha256_file(phase1_check_revision(cfg, identity)))
    expect_false(dir.exists(source_safe_path(source_operational_root(cfg), "locks/demo.base.lock")))
    phase1_check_commit(cfg, identity, latest, 3)
    expect_equal(read_source_state(cfg, identity)$state_revision, latest$state_revision + 1)
  }
  cfg <- phase1_check_config(); identity <- phase1_check_identity()
  state <- phase1_check_commit(cfg, identity, new_source_state(identity))
  hooks <- list(after_temp_write = function(context) writeLines("{partial", context$temporary))
  expect_error(phase1_check_commit(cfg, identity, state, 2, hooks = hooks), "invalid_json")
  expect_equal(read_source_state(cfg, identity)$state_revision, 1)
  expect_true(any(startsWith(list.files(dirname(phase1_check_revision(cfg, identity)), all.files = TRUE), ".pending-")))
  phase1_check_commit(cfg, identity, state, 3)
  expect_equal(read_source_state(cfg, identity)$state_revision, 2)
  # A competing destination is preserved, even if it is itself malformed.
  cfg <- phase1_check_config()
  state <- phase1_check_commit(cfg, identity, new_source_state(identity))
  hooks <- list(before_rename = function(context) writeLines("preserve competing destination", context$destination))
  expect_error(phase1_check_commit(cfg, identity, state, 2, hooks = hooks), "destination_exists")
  expect_identical(readLines(phase1_check_revision(cfg, identity, 2)), "preserve competing destination")
  expect_error(read_source_state(cfg, identity), "invalid_json")
})

test_that("1B I content preserves exact bytes and validates size, hash and regular files", {
  cfg <- phase1_check_config()
  bytes <- c(as.raw(c(239, 187, 191)), charToRaw("synthetic;ação\r\n"), as.raw(c(0, 255)))
  blob <- store_source_content(cfg, "demo.base", "json", bytes)
  expect_false(blob$reused)
  expect_identical(blob$content$sha256, digest::digest(bytes, algo = "sha256", serialize = FALSE))
  expect_true(verify_source_content(cfg, "demo.base", "json", blob$content)$valid)
  path <- source_safe_path(source_operational_root(cfg), blob$content$relative_path)
  expect_identical(readBin(path, "raw", n = length(bytes)), bytes)
  original <- file.info(path)$mtime
  again <- store_source_content(cfg, "demo.base", "json", bytes)
  expect_true(again$reused)
  expect_identical(blob$content, again$content)
  expect_identical(file.info(path)$mtime, original)
  bad <- blob$content; bad$bytes <- bad$bytes + 1
  expect_identical(verify_source_content(cfg, "demo.base", "json", bad)$code, "content_size_mismatch")
  bad <- blob$content; bad$sha256 <- paste(rep("a", 64), collapse = "")
  expect_false(verify_source_content(cfg, "demo.base", "json", bad)$valid)
  expect_false(verify_source_content(cfg, "demo.base", "csv", blob$content)$valid)
  expect_false(verify_source_content(cfg, "demo.subset", "json", blob$content)$valid)
  con <- file(path, "wb"); writeBin(as.raw(rep(1, length(bytes))), con); close(con)
  expect_identical(verify_source_content(cfg, "demo.base", "json", blob$content)$code, "content_hash_mismatch")
  expect_error(store_source_content(cfg, "demo.base", "json", bytes), "content_hash_mismatch")
  expect_identical(readBin(path, "raw", n = length(bytes)), as.raw(rep(1, length(bytes))))
  expect_error(store_source_content(cfg, "demo.base", "json", "not raw"), "raw")
  cfg <- phase1_check_config()
  empty <- store_source_content(cfg, "demo.base", "csv", raw())
  expect_true(verify_source_content(cfg, "demo.base", "csv", empty$content)$valid)
  missing <- empty$content
  unlink(source_safe_path(source_operational_root(cfg), missing$relative_path))
  expect_identical(verify_source_content(cfg, "demo.base", "csv", missing)$code, "content_missing")
  dir.create(source_safe_path(source_operational_root(cfg), missing$relative_path))
  expect_identical(verify_source_content(cfg, "demo.base", "csv", missing)$code, "content_not_regular")
})

test_that("1B I paths reject traversal, absolute paths and symlink escapes", {
  cfg <- phase1_check_config(); root <- source_operational_root(cfg)
  for (path in c("../outside", "../../outside", "/tmp/outside", "C:/outside", "a/../b", "a/./b", "a\\b", "a//b", "a/")) {
    expect_error(source_safe_path(root, path), "BLOCK", info = path)
  }
  blob <- store_source_content(cfg, "demo.base", "json", charToRaw("synthetic"))
  for (path in c("../outside", "/tmp/outside", "../../outside")) {
    bad <- blob$content; bad$relative_path <- path
    expect_false(verify_source_content(cfg, "demo.base", "json", bad)$valid)
  }
  expect_identical(source_safe_path(root, blob$content$relative_path), file.path(root, blob$content$relative_path))
  outside <- withr::local_tempdir()
  target <- file.path(outside, "synthetic.bin"); writeBin(charToRaw("synthetic"), target)
  alias <- file.path(root, "alias")
  if (!suppressWarnings(file.symlink(outside, alias))) skip("Local symlinks unavailable; deterministic traversal tests passed")
  expect_error(source_safe_path(root, "alias/synthetic.bin"), "symlink_path")
  expect_error(source_safe_path(root, "alias/missing/file"), "symlink_path")
  path <- source_safe_path(root, blob$content$relative_path)
  unlink(path); expect_true(file.symlink(target, path))
  expect_identical(verify_source_content(cfg, "demo.base", "json", blob$content)$code, "symlink_path")
  expect_error(store_source_content(cfg, "demo.base", "json", charToRaw("synthetic")), "symlink_path")
  expect_identical(readBin(target, "raw", n = 9), charToRaw("synthetic"))
  cfg <- phase1_check_config()
  dir.create(cfg$data_dir)
  expect_true(file.symlink(outside, file.path(cfg$data_dir, "cache")))
  expect_error(acquire_source_lock(cfg, "demo.base"), "symlink_path")
  expect_false(dir.exists(file.path(outside, "sources")))
})

test_that("1B I rejected and orphan candidates never become validated implicitly", {
  cfg <- phase1_check_config(); identity <- phase1_check_identity()
  a <- store_source_content(cfg, "demo.base", "json", charToRaw("synthetic A"))$content
  b <- store_source_content(cfg, "demo.base", "json", charToRaw("synthetic B"))$content
  state <- source_state_candidate(new_source_state(identity), a, clock = phase1_check_clock)
  state <- source_state_promote(state, phase1_check_validation(), phase1_check_clock)
  state <- phase1_check_commit(cfg, identity, state, type = "content_validated", sha = a$sha256)
  expect_identical(state$validated_content$sha256, a$sha256)
  state <- source_state_candidate(state, b, phase1_check_validation("block"), phase1_check_clock)
  state <- phase1_check_commit(cfg, identity, state, 2, "candidate_stored", b$sha256)
  expect_identical(state$latest_candidate$sha256, b$sha256)
  expect_identical(state$latest_candidate$validation$decision, "block")
  expect_identical(state$validated_content$sha256, a$sha256)
  expect_error(source_state_promote(state, phase1_check_validation("block")), "invalid_content_validation")
  promoted <- source_state_promote(state, phase1_check_validation(), phase1_check_clock)
  expect_error(phase1_check_commit(cfg, identity, promoted, 3, "candidate_stored", b$sha256), "implicit_validated_transition")
  state <- phase1_check_commit(cfg, identity, promoted, 3, "content_validated", b$sha256)
  expect_identical(state$validated_content$sha256, b$sha256)
  expect_null(state$validated_content$etag_raw)
  expect_null(state$validated_content$last_modified_raw)
  expect_false(state$validated_content$conditional_reuse_allowed)
  store_source_content(cfg, "demo.base", "json", charToRaw("synthetic orphan"))
  expect_identical(read_source_state(cfg, identity)$validated_content$sha256, b$sha256)
  cfg <- phase1_check_config()
  store_source_content(cfg, "demo.base", "json", charToRaw("synthetic orphan"))
  expect_null(read_source_state(cfg, identity))
  expect_error(source_state_promote(new_source_state(identity), phase1_check_validation()), "no_candidate")
  # Event/state metadata has no slots for payloads or secrets.
  event <- phase1_check_event(identity); event$payload <- "forbidden"
  expect_error(validate_source_event(event, identity), "invalid_object_fields")
  event <- phase1_check_event(identity); event$code <- "contact@example.invalid"
  expect_error(validate_source_event(event, identity), "invalid_event_code")
  validation <- phase1_check_validation(); validation$payload <- "forbidden"
  expect_error(source_state_candidate(new_source_state(identity), b, validation), "invalid_object_fields")
})

test_that("1B I state namespaces isolate sources, representations and request identities", {
  cfg <- phase1_check_config()
  identities <- list(phase1_check_identity(), phase1_check_identity("csv"), phase1_check_identity(query = "?v=2"),
    phase1_check_identity(source_id = "demo.subset"))
  for (i in seq_along(identities)) {
    identity <- identities[[i]]
    expect_null(read_source_state(cfg, identity))
    phase1_check_commit(cfg, identity, new_source_state(identity), i)
    expect_equal(read_source_state(cfg, identity)$state_revision, 1)
  }
  expect_length(unique(vapply(identities, source_revisions_relative, character(1))), 4)
  state <- read_source_state(cfg, identities[[1]])
  expect_error(validate_source_state(state, identities[[2]]), "state_identity_mismatch")
  expect_error(validate_source_state(state, identities[[3]]), "state_identity_mismatch")
  expect_error(validate_source_state(state, identities[[4]]), "state_identity_mismatch")
})

test_that("1B I real local contenders cannot acquire the same source lock", {
  cfg <- phase1_check_config(); coord <- withr::local_tempdir(); api <- phase1_check_lock_api()
  worker <- function(config, directory, number, api) {
    deadline <- Sys.time() + 15
    while (!file.exists(file.path(directory, "start"))) {
      if (Sys.time() > deadline) stop("Synthetic start barrier timed out")
      Sys.sleep(0.01)
    }
    lock <- tryCatch(api$acquire_source_lock(config, "demo.base"), error = identity)
    acquired <- !inherits(lock, "error")
    result_path <- file.path(directory, paste0(number, ".rds"))
    temporary <- paste0(result_path, ".pending")
    saveRDS(list(acquired = acquired, code = if (acquired) NULL else lock$code,
      error = if (acquired) NULL else conditionMessage(lock)), temporary)
    if (!file.rename(temporary, result_path)) stop("Synthetic barrier promotion failed")
    if (acquired) {
      on.exit(api$release_source_lock(config, lock), add = TRUE)
      while (!file.exists(file.path(directory, "release"))) {
        if (Sys.time() > deadline) stop("Synthetic release barrier timed out")
        Sys.sleep(0.01)
      }
    }
    acquired
  }
  processes <- list()
  on.exit(for (p in processes) if (p$is_alive()) p$kill(), add = TRUE)
  for (i in 1:2) processes[[i]] <- callr::r_bg(worker, list(cfg, coord, i, api), supervise = TRUE)
  file.create(file.path(coord, "start"))
  deadline <- Sys.time() + 15
  results <- file.path(coord, paste0(1:2, ".rds"))
  while (!all(file.exists(results)) && Sys.time() < deadline) Sys.sleep(0.02)
  expect_true(all(file.exists(results)))
  if (!all(file.exists(results))) {
    for (p in processes) if (!p$is_alive()) p$get_result()
    stop("Local lock contenders did not produce results")
  }
  observed <- lapply(results, readRDS)
  expect_identical(sort(vapply(observed, `[[`, logical(1), "acquired")), c(FALSE, TRUE),
    info = paste(vapply(observed, function(x) x$error %||% "acquired", character(1)), collapse = "; "))
  loser <- Filter(function(r) !r$acquired, observed)[[1]]
  expect_identical(loser$code, "lock_busy")
  file.create(file.path(coord, "release"))
  for (p in processes) { p$wait(10000); expect_false(p$is_alive()); p$get_result() }
  expect_false(dir.exists(source_safe_path(source_operational_root(cfg), "locks/demo.base.lock")))
})

test_that("1B I revision checksums exclude self and include every linked value", {
  cfg <- phase1_check_config(); identity <- phase1_check_identity()
  phase1_check_commit(cfg, identity, new_source_state(identity, "synthetic-ação"))
  record <- source_read_json(phase1_check_revision(cfg, identity))
  changed <- record; changed$record_sha256 <- paste(rep("f", 64), collapse = "")
  expect_identical(source_record_checksum(changed), record$record_sha256)
  changed <- record; changed$previous_record_sha256 <- paste(rep("f", 64), collapse = "")
  expect_false(identical(source_record_checksum(changed), record$record_sha256))
  changed <- record; changed$state_after$registry_revision_seen <- "synthetic-other"
  expect_false(identical(source_record_checksum(changed), record$record_sha256))
  expect_identical(record$record_sha256, source_canonical_sha256(record[!names(record) %in% "record_sha256"]))
  record$event <- c(record$event, record$event["event_id"])
  expect_error(source_record_checksum(record), "BLOCK")
})

test_that("1B I atomic blob failures preserve evidence and never initialize state", {
  for (point in c("before_temp_write", "after_temp_write", "before_rename", "after_rename")) {
    cfg <- phase1_check_config(); identity <- phase1_check_identity()
    a <- store_source_content(cfg, "demo.base", "json", charToRaw("synthetic A"))$content
    hooks <- stats::setNames(list(function(context) stop("synthetic blob failure")), point)
    expect_error(store_source_content(cfg, "demo.base", "json", charToRaw("synthetic B"), hooks = hooks), "synthetic blob failure")
    expect_true(verify_source_content(cfg, "demo.base", "json", a)$valid)
    expect_null(read_source_state(cfg, identity))
    next_blob <- store_source_content(cfg, "demo.base", "json", charToRaw("synthetic B"))
    expect_identical(next_blob$reused, point == "after_rename")
    expect_true(verify_source_content(cfg, "demo.base", "json", next_blob$content)$valid)
  }
  cfg <- phase1_check_config()
  hooks <- list(after_temp_write = function(context) writeBin(charToRaw("truncated"), context$temporary))
  expect_error(store_source_content(cfg, "demo.base", "json", charToRaw("synthetic complete body"), hooks = hooks), "blob_write_integrity")
  expect_true(any(startsWith(list.files(file.path(source_operational_root(cfg), "content", "demo.base", "json"), all.files = TRUE), ".pending-")))
})

test_that("1B I a held source lock spans JSON and CSV and preserves unexpected files", {
  cfg <- phase1_check_config()
  lock <- acquire_source_lock(cfg, "demo.base")
  expect_error(store_source_content(cfg, "demo.base", "json", raw()), "lock_busy")
  expect_error(store_source_content(cfg, "demo.base", "csv", raw()), "lock_busy")
  json <- store_source_content(cfg, "demo.base", "json", raw(), lock = lock)
  csv <- store_source_content(cfg, "demo.base", "csv", raw(), lock = lock)
  expect_false(identical(json$content$relative_path, csv$content$relative_path))
  extra <- source_safe_path(lock$root, "locks/demo.base.lock/preserve.txt")
  writeLines("synthetic evidence", extra)
  expect_error(release_source_lock(cfg, lock), "unexpected_lock_files")
  expect_identical(readLines(extra), "synthetic evidence")
  expect_true(assert_source_lock(cfg, "demo.base", lock))
  # This isolated test intentionally leaves its own lock/evidence untouched.
})

test_that("1B I read refuses unsafe stored references and corrupt validated bytes", {
  cfg <- phase1_check_config(); identity <- phase1_check_identity()
  blob <- store_source_content(cfg, "demo.base", "json", charToRaw("synthetic A"))$content
  state <- source_state_candidate(new_source_state(identity), blob, clock = phase1_check_clock)
  state <- source_state_promote(state, phase1_check_validation(), phase1_check_clock)
  phase1_check_commit(cfg, identity, state, type = "content_validated", sha = blob$sha256)
  path <- source_safe_path(source_operational_root(cfg), blob$relative_path)
  writeBin(charToRaw("synthetic B"), path)
  expect_error(read_source_state(cfg, identity), "content_hash_mismatch")
  record_path <- phase1_check_revision(cfg, identity)
  phase1_check_rewrite(record_path, function(r) {r$state_after$validated_content$relative_path <- "../outside"; r})
  expect_error(read_source_state(cfg, identity), "invalid_content_reference")
  expect_true(file.exists(path))
})

test_that("1B I local state never calls HTTP, collection or preparation", {
  v02_forbid_http()
  testthat::local_mocked_bindings(collect_sampa_data = function(...) stop("COLLECT FORBIDDEN"),
    prepare_equipment_data = function(...) stop("PREPARE FORBIDDEN"), .package = "sampamaisrural")
  testthat::local_mocked_bindings(download.file = function(...) stop("NETWORK FORBIDDEN"), .package = "utils")
  cfg <- phase1_check_config(); identity <- phase1_check_identity()
  before <- c("raw", "processed")
  for (dir in before) {
    path <- file.path(cfg$data_dir, dir); dir.create(path, recursive = TRUE)
    writeLines("synthetic protected sentinel", file.path(path, "sentinel"))
  }
  hashes <- vapply(before, function(dir) sha256_file(file.path(cfg$data_dir, dir, "sentinel")), character(1))
  blob <- store_source_content(cfg, "demo.base", "json", charToRaw("synthetic only"))$content
  state <- source_state_candidate(new_source_state(identity), blob, clock = phase1_check_clock)
  phase1_check_commit(cfg, identity, state, type = "candidate_stored", sha = blob$sha256)
  expect_identical(hashes, vapply(before, function(dir) sha256_file(file.path(cfg$data_dir, dir, "sentinel")), character(1)))
  for (dir in before) expect_identical(list.files(file.path(cfg$data_dir, dir)), "sentinel")
  expect_false(any(grepl("manifest|snapshot", list.files(cfg$data_dir, recursive = TRUE))))
  expect_false(exists("sampa_check_updates", asNamespace("sampamaisrural"), inherits = FALSE))
  expect_false("source_request_identity" %in% getNamespaceExports("sampamaisrural"))
})

test_that("1B I P2 roots stay lexical and stable throughout the lock lifecycle", {
  base <- withr::local_tempdir()
  dir.create(file.path(base, "existing"))
  withr::local_dir(base)
  paths <- c(file.path(base, "existing"), file.path(base, "new", "..", "data"),
    file.path(base, ".", "missing", ".", "..", "data", "."), "new/../data")
  for (path in paths) {
    cfg <- list(data_dir = path)
    before <- source_operational_root(cfg)
    expected <- file.path(base, if (path == paths[1]) "existing" else "data", "cache", "sources")
    expect_identical(before, expected, info = path)
    lock <- acquire_source_lock(cfg, "demo.base", phase1_check_clock, function() "synthetic-root")
    expect_identical(source_operational_root(cfg), before, info = path)
    expect_identical(lock$root, before, info = path)
    blob <- store_source_content(cfg, "demo.base", "json", charToRaw("synthetic root"), lock = lock)
    expect_true(verify_source_content(cfg, "demo.base", "json", blob$content)$valid)
    wrong <- lock; wrong$owner$token <- "wrong-root-owner"
    expect_error(release_source_lock(cfg, wrong), "lock_not_owned")
    wrong <- lock; wrong$root <- paste0(before, "-different")
    expect_error(release_source_lock(cfg, wrong), "lock_identity_mismatch")
    expect_true(release_source_lock(cfg, lock))
    expect_false(dir.exists(source_safe_path(before, "locks/demo.base.lock")))
    again <- acquire_source_lock(cfg, "demo.base")
    expect_true(assert_source_lock(cfg, "demo.base", again))
    expect_true(release_source_lock(cfg, again))
    expect_identical(source_operational_root(cfg), before)
  }
  expect_false(dir.exists(file.path(base, "new")))
  expect_false(dir.exists(file.path(base, "missing")))
})

test_that("1B I P2 lexical roots do not hide links or relax content traversal", {
  base <- withr::local_tempdir(); outside <- withr::local_tempdir()
  cfg <- list(data_dir = file.path(base, "new", "..", "data"))
  root <- source_operational_root(cfg)
  for (path in c("../outside", "../../outside", "a/../b", "a/./b", "/tmp/outside")) {
    expect_error(source_safe_path(root, path), "unsafe_relative_path")
  }
  link <- file.path(base, "alias")
  if (!suppressWarnings(file.symlink(outside, link))) skip("Local symlinks unavailable")
  expect_error(source_operational_root(list(data_dir = file.path(link, "..", "data"))), "symlink_path")
  expect_error(source_operational_root(list(data_dir = file.path(link, "new", "..", "data"))), "symlink_path")
  dir.create(file.path(base, "data"), recursive = TRUE)
  expect_true(file.symlink(outside, file.path(base, "data", "cache")))
  expect_error(acquire_source_lock(cfg, "demo.base"), "symlink_path")
  expect_identical(list.files(outside, all.files = TRUE, no.. = TRUE), character())
})

test_that("1B I P2 revision absence is distinguished from a listable empty directory", {
  cfg <- phase1_check_config(); identity <- phase1_check_identity()
  path <- source_safe_path(source_operational_root(cfg), source_revisions_relative(identity))
  expect_identical(source_revision_listing(path)$status, "state_absent")
  expect_null(read_source_state(cfg, identity))
  expect_false(dir.exists(cfg$data_dir))
  dir.create(path, recursive = TRUE)
  expect_identical(source_revision_listing(path), list(status = "revisions_empty", entries = character()))
  expect_null(read_source_state(cfg, identity))
  state <- phase1_check_commit(cfg, identity, new_source_state(identity))
  expect_identical(source_revision_listing(path)$status, "revisions_available")
  expect_identical(source_canonical_json(read_source_state(cfg, identity)), source_canonical_json(state))
  expect_identical(list.files(path), "000000000001.json")
})

test_that("1B I P2 listing errors, warnings and invalid results always block", {
  cfg <- phase1_check_config(); identity <- phase1_check_identity()
  state <- phase1_check_commit(cfg, identity, new_source_state(identity))
  revision <- phase1_check_revision(cfg, identity); path <- dirname(revision)
  before <- readBin(revision, "raw", n = file.info(revision)$size)
  listing <- source_revision_listing
  failures <- list(function(path) stop("synthetic listing error"),
    function(path) { warning("synthetic listing warning"); character() },
    function(path) NULL, function(path) NA_character_)
  for (failure in failures) local({
    testthat::local_mocked_bindings(source_revision_listing = function(path) listing(path, list_entries = failure),
      .package = "sampamaisrural")
    expect_error(read_source_state(cfg, identity), "revisions_unreadable")
    expect_error(phase1_check_commit(cfg, identity, state, 2), "revisions_unreadable")
    expect_identical(readBin(revision, "raw", n = length(before)), before)
    expect_identical(list.files(path), "000000000001.json")
  })
  expect_equal(read_source_state(cfg, identity)$state_revision, 1)
})

test_that("1B I P2 real inaccessible revisions block without repairing history", {
  cfg <- phase1_check_config(); identity <- phase1_check_identity()
  state <- phase1_check_commit(cfg, identity, new_source_state(identity))
  state <- phase1_check_commit(cfg, identity, state, 2)
  directory <- dirname(phase1_check_revision(cfg, identity))
  files <- list.files(directory, full.names = TRUE)
  before <- vapply(files, sha256_file, character(1))
  mode <- file.info(directory)$mode
  on.exit(Sys.chmod(directory, mode), add = TRUE)
  Sys.chmod(directory, "0300")
  if (file.access(directory, 4) == 0L) skip("Platform/user cannot demonstrate POSIX read denial; injected listing failures tested separately")
  expect_true(dir.exists(directory))
  expect_identical(unname(file.access(directory, 4)), -1L)
  expect_error(source_revision_listing(directory), "revisions_unreadable")
  expect_error(read_source_state(cfg, identity), "revisions_unreadable")
  expect_error(phase1_check_commit(cfg, identity, state, 3), "revisions_unreadable")
  expect_identical(file.info(directory)$mode, as.octmode("300"))
  Sys.chmod(directory, mode)
  expect_identical(list.files(directory, full.names = TRUE), files)
  expect_identical(vapply(files, sha256_file, character(1)), before)
  expect_identical(source_canonical_json(read_source_state(cfg, identity)), source_canonical_json(state))
  # An unsearchable ancestor must not make its descendants appear absent.
  parent <- dirname(directory); parent_mode <- file.info(parent)$mode
  on.exit(Sys.chmod(parent, parent_mode), add = TRUE)
  Sys.chmod(parent, "0600")
  expect_error(read_source_state(cfg, identity), "revisions_unreadable")
  Sys.chmod(parent, parent_mode)
  expect_equal(read_source_state(cfg, identity)$state_revision, 2)
  # Permission restoration never substitutes for validating the checksum chain.
  phase1_check_rewrite(files[2], function(r) {r$event$code <- "synthetic_changed"; r}, resign = FALSE)
  expect_error(read_source_state(cfg, identity), "invalid_revision_checksum_chain")
  expect_true(all(file.exists(files)))
})

test_that("1B I P2 blob verification returns structured integrity and path diagnostics", {
  cfg <- phase1_check_config()
  blob <- store_source_content(cfg, "demo.base", "json", charToRaw("synthetic A"))$content
  path <- source_safe_path(source_operational_root(cfg), blob$relative_path)
  check_block <- function(content, code) {
    expect_identical(verify_source_content(cfg, "demo.base", "json", content),
      list(valid = FALSE, decision = "block", code = code))
  }
  expect_true(verify_source_content(cfg, "demo.base", "json", blob)$valid)
  missing <- store_source_content(cfg, "demo.base", "json", charToRaw("synthetic missing"))$content
  unlink(source_safe_path(source_operational_root(cfg), missing$relative_path))
  check_block(missing, "content_missing")
  wrong_size <- blob; wrong_size$bytes <- blob$bytes + 1
  check_block(wrong_size, "content_size_mismatch")
  writeBin(charToRaw("synthetic B"), path)
  check_block(blob, "content_hash_mismatch")
  traversal <- blob; traversal$relative_path <- "../outside"
  check_block(traversal, "invalid_content_reference")
  outside <- withr::local_tempfile(); writeBin(charToRaw("synthetic A"), outside)
  unlink(path)
  if (!suppressWarnings(file.symlink(outside, path))) skip("Local symlinks unavailable")
  check_block(blob, "symlink_path")
  expect_identical(readBin(outside, "raw", n = 11L), charToRaw("synthetic A"))
})

test_that("1B I P2 unreadable blobs block and validate again after POSIX permission restore", {
  cfg <- phase1_check_config()
  blob <- store_source_content(cfg, "demo.base", "json", charToRaw("synthetic only"))$content
  path <- source_safe_path(source_operational_root(cfg), blob$relative_path)
  mode <- file.info(path)$mode
  on.exit(Sys.chmod(path, mode), add = TRUE)
  Sys.chmod(path, "0000")
  if (file.access(path, 4) == 0L) skip("Platform/user cannot demonstrate POSIX blob read denial; injected failures tested separately")
  result <- tryCatch(verify_source_content(cfg, "demo.base", "json", blob), error = identity)
  expect_false(inherits(result, "error"))
  expect_identical(result, list(valid = FALSE, decision = "block", code = "content_unreadable"))
  required <- tryCatch(source_require_content(cfg, "demo.base", "json", blob), error = identity)
  expect_s3_class(required, "source_state_block")
  expect_false(inherits(required, "simpleError"))
  expect_identical(required$decision, "block")
  expect_identical(required$code, "content_unreadable")
  expect_identical(file.info(path)$mode, as.octmode("0"))
  Sys.chmod(path, mode)
  expect_true(verify_source_content(cfg, "demo.base", "json", blob)$valid)
  expect_true(source_require_content(cfg, "demo.base", "json", blob))
  expect_identical(readBin(path, "raw", n = 14L), charToRaw("synthetic only"))
  expect_identical(sha256_file(path), blob$sha256)
})

test_that("1B I P2 known filesystem hash failures block even after access recovers", {
  cfg <- phase1_check_config()
  blob <- store_source_content(cfg, "demo.base", "json", charToRaw("synthetic only"))$content
  for (prefix in c("The file does not exist: ", "The specified pathname is not a file: ",
      "The specified file is not readable: ", "Cannot open input file: ")) local({
    # Match the file-I/O errors of the existing digest backend, with readable
    # bytes retained. This models an open failure/race without relying on chmod.
    testthat::local_mocked_bindings(sha256_file = function(path) stop(simpleError(paste0(prefix, path))),
      .package = "sampamaisrural")
    expect_identical(verify_source_content(cfg, "demo.base", "json", blob),
      list(valid = FALSE, decision = "block", code = "content_unreadable"))
    required <- tryCatch(source_require_content(cfg, "demo.base", "json", blob), error = identity)
    expect_s3_class(required, "source_state_block")
    expect_identical(required$code, "content_unreadable")
    expect_false(inherits(required, "simpleError"))
  })
  expect_true(verify_source_content(cfg, "demo.base", "json", blob)$valid)
})

test_that("1B I P2 metadata failures block and unexpected programming errors remain visible", {
  cfg <- phase1_check_config()
  blob <- store_source_content(cfg, "demo.base", "json", charToRaw("synthetic only"))$content
  stat <- source_content_file_info
  failures <- list(function(path) { warning("synthetic stat failure"); data.frame(size = NA_real_) },
    function(path) data.frame(size = NA_real_), function(path) stop("synthetic stat access error"))
  for (failure in failures) local({
    testthat::local_mocked_bindings(source_content_file_info = function(path) stat(path, stat_file = failure),
      .package = "sampamaisrural")
    expect_identical(verify_source_content(cfg, "demo.base", "json", blob),
      list(valid = FALSE, decision = "block", code = "content_unreadable"))
  })
  for (binding in c("validate_source_content_reference", "sha256_file")) local({
    bug <- simpleError("synthetic programming defect")
    replacement <- stats::setNames(list(function(...) stop(bug)), binding)
    do.call(testthat::local_mocked_bindings, c(replacement, list(.package = "sampamaisrural")))
    expect_identical(tryCatch(verify_source_content(cfg, "demo.base", "json", blob), error = identity), bug)
    expect_identical(tryCatch(source_require_content(cfg, "demo.base", "json", blob), error = identity), bug)
  })
  local({
    bug <- simpleError("Cannot open input file: unrelated-programming-path")
    testthat::local_mocked_bindings(sha256_file = function(...) stop(bug), .package = "sampamaisrural")
    expect_identical(tryCatch(verify_source_content(cfg, "demo.base", "json", blob), error = identity), bug)
  })
  expect_true(verify_source_content(cfg, "demo.base", "json", blob)$valid)
})

test_that("1B I special file metadata proves regularity without reading content", {
  directory <- withr::local_tempdir()
  # Spaces, quotes, shell syntax and Unicode must remain literal path data.
  path <- file.path(directory, "synthetic ' ação $(false);.json")
  writeLines('{"synthetic":true}', path)
  expect_true(source_file_is_regular(path))
  expect_true(source_require_regular_file(path, "not_regular_json_file"))
  expect_identical(source_read_json(path), list(synthetic = TRUE))
  expect_false(source_file_is_regular(directory))
  expect_error(source_read_json(directory), "not_regular_json_file", class = "source_state_block")
  expect_false(source_file_is_regular(file.path(directory, "absent")))
  expect_identical(source_file_is_regular(path, platform = "unsupported"), NA)
  expect_identical(source_file_is_regular(path, shell = ""), NA)
  expect_identical(source_file_is_regular(path, shell = file.path(directory, "missing-shell")), NA)
  mode <- file.info(path)$mode
  on.exit(Sys.chmod(path, mode), add = TRUE)
  Sys.chmod(path, "0000")
  # File type and permission to read are independent properties.
  expect_true(source_file_is_regular(path))
  Sys.chmod(path, mode)
  link <- file.path(directory, "alias")
  if (!suppressWarnings(file.symlink(path, link))) skip("Local symlinks unavailable")
  expect_error(source_read_json(link), "symlink_path", class = "source_state_block")
})

test_that("1B I special file unknown metadata fails closed before hash or JSON read", {
  cfg <- phase1_check_config()
  blob <- store_source_content(cfg, "demo.base", "json", charToRaw("synthetic"))$content
  path <- source_safe_path(source_operational_root(cfg), blob$relative_path)
  for (unknown in list(NA, NULL, logical(), "regular")) local({
    testthat::local_mocked_bindings(source_file_is_regular = function(...) unknown,
      sha256_file = function(...) stop("HASH MUST NOT RUN"), .package = "sampamaisrural")
    expect_identical(verify_source_content(cfg, "demo.base", "json", blob),
      list(valid = FALSE, decision = "block", code = "content_not_regular"))
    expect_error(source_require_content(cfg, "demo.base", "json", blob), "content_not_regular", class = "source_state_block")
    expect_error(source_read_json(path), "not_regular_json_file", class = "source_state_block")
  })
  local({
    bug <- simpleError("synthetic type-inspection programming defect")
    testthat::local_mocked_bindings(source_file_is_regular = function(...) stop(bug), .package = "sampamaisrural")
    expect_identical(tryCatch(verify_source_content(cfg, "demo.base", "json", blob), error = identity), bug)
    expect_identical(tryCatch(source_read_json(path), error = identity), bug)
  })
  expect_true(verify_source_content(cfg, "demo.base", "json", blob)$valid)
})

test_that("1B I special real FIFOs block before reads and leave source locks releasable", {
  skip_if(.Platform$OS.type != "unix", "Real FIFO regression requires POSIX")
  skip_if(!nzchar(Sys.which("mkfifo")), "mkfifo unavailable; unknown-type rejection tested separately")
  cfg <- phase1_check_config(); identity <- phase1_check_identity()
  sha <- digest::digest(raw(), algo = "sha256", serialize = FALSE)
  content <- list(sha256 = sha, bytes = 0L, relative_path = source_content_relative("demo.base", "json", sha))
  path <- source_safe_path(source_operational_root(cfg), content$relative_path)
  revision <- phase1_check_revision(cfg, identity)
  dir.create(dirname(path), recursive = TRUE)
  dir.create(dirname(revision), recursive = TRUE)
  expect_identical(system2(Sys.which("mkfifo"), shQuote(path)), 0L)
  expect_identical(system2(Sys.which("mkfifo"), shQuote(revision)), 0L)
  # Serialize current internal definitions, including uninstalled changes. A
  # bounded child is essential: a regression must not hang the test process.
  api <- phase1_check_lock_api()
  ns <- asNamespace("sampamaisrural")
  for (name in c("store_source_content", "with_source_lock", "verify_source_content",
      "validate_source_content_reference", "sha256_file", "read_source_state",
      "read_source_revisions", "validate_source_request_identity")) {
    fun <- get(name, ns); environment(fun) <- api; assign(name, fun, api)
  }
  result <- callr::r(function(api, cfg, content, path, revision, request_identity) {
    capture_block <- function(expr) tryCatch(force(expr), source_state_block = function(e)
      list(class = class(e), code = e$code, decision = e$decision))
    regular <- api$store_source_content(cfg, "demo.base", "json", charToRaw("synthetic regular"))$content
    regular_ok <- api$verify_source_content(cfg, "demo.base", "json", regular)$valid
    # These are real, unmocked calls against FIFOs with no writer.
    verified <- api$verify_source_content(cfg, "demo.base", "json", content)
    stored <- capture_block(api$store_source_content(cfg, "demo.base", "json", raw()))
    lock_path <- file.path(api$source_operational_root(cfg), "locks", "demo.base.lock")
    released <- !dir.exists(lock_path)
    next_lock <- api$acquire_source_lock(cfg, "demo.base")
    acquired <- api$assert_source_lock(cfg, "demo.base", next_lock)
    api$release_source_lock(cfg, next_lock)
    json <- capture_block(api$source_read_json(revision))
    state <- capture_block(api$read_source_state(cfg, request_identity))
    # Instrument only the forbidden paths to prove neither hash nor JSON read
    # is attempted. Reads of the lock owner's regular JSON remain permitted.
    hash <- api$sha256_file
    api$sha256_file <- function(p) {
      if (identical(p, path)) stop("FIFO HASH ATTEMPT")
      hash(p)
    }
    api$readLines <- function(con, ...) {
      if (identical(con, revision)) stop("FIFO READ ATTEMPT")
      base::readLines(con, ...)
    }
    guarded <- api$verify_source_content(cfg, "demo.base", "json", content)
    guarded_store <- capture_block(api$store_source_content(cfg, "demo.base", "json", raw()))
    guarded_json <- capture_block(api$source_read_json(revision))
    # Also check temporary-file validation after an injected special file.
    temporary <- NULL
    hooks <- list(after_temp_write = function(context) {
      temporary <<- context$temporary
      unlink(temporary) # Only this synthetic temporary is replaced for the test.
      stopifnot(system2(Sys.which("mkfifo"), shQuote(temporary)) == 0L)
    })
    temp_block <- capture_block(api$store_source_content(cfg, "demo.base", "json", charToRaw("synthetic temporary"), hooks = hooks))
    list(regular = regular_ok, fifo_regular = api$source_file_is_regular(path), verified = verified,
      stored = stored, released = released, acquired = acquired, json = json, state = state,
      guarded = guarded, guarded_store = guarded_store, guarded_json = guarded_json, temp_block = temp_block,
      temporary_preserved = file.exists(temporary) && !api$source_file_is_regular(temporary),
      lock_absent = !dir.exists(lock_path), fifo_preserved = file.exists(path) && file.exists(revision))
  }, list(api, cfg, content, path, revision, identity), timeout = 20)
  expect_true(result$regular)
  expect_false(result$fifo_regular)
  expect_identical(result$verified, list(valid = FALSE, decision = "block", code = "content_not_regular"))
  for (name in c("stored", "guarded_store", "temp_block")) {
    expect_identical(result[[name]]$code, "content_not_regular")
    expect_true("source_state_block" %in% result[[name]]$class)
  }
  expect_true(result$released)
  expect_true(result$acquired)
  for (name in c("json", "state", "guarded_json")) {
    expect_identical(result[[name]]$code, "not_regular_json_file")
    expect_true("source_state_block" %in% result[[name]]$class)
  }
  expect_identical(result$guarded, result$verified)
  expect_true(result$lock_absent)
  expect_true(result$fifo_preserved)
  expect_true(result$temporary_preserved)
})
