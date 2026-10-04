# Checkpoint 1B, step I. Local operational state only; all functions internal.
source_state_block <- function(code) {
  stop(structure(list(message = paste0("Source state BLOCK: ", code), call = NULL,
    code = code, decision = "block"), class = c("source_state_block", "error", "condition")))
}

source_state_object <- function(x, fields, required = fields) {
  if (!is.list(x) || is.null(names(x)) || anyNA(names(x)) || anyDuplicated(names(x)) ||
      any(!names(x) %in% fields) || any(!required %in% names(x))) source_state_block("invalid_object_fields")
  invisible(TRUE)
}

source_state_integer <- function(x, minimum = 0, maximum = .Machine$integer.max) {
  is.numeric(x) && length(x) == 1L && !is.na(x) && is.finite(x) && x >= minimum && x <= maximum && x == floor(x)
}

source_state_hash <- function(x) source_string(x) && grepl("^[a-f0-9]{64}$", x)
source_state_token <- function(x) source_string(x) && grepl("^[A-Za-z0-9_-]+$", x)
source_state_id <- function() basename(tempfile("source-"))
source_state_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

source_state_time <- function(x) {
  if (!source_string(x) || !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", x)) return(FALSE)
  parsed <- suppressWarnings(as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  !is.na(parsed) && identical(format(parsed, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), x)
}

source_state_namespace <- function(source_id, representation = NULL) {
  if (!source_string(source_id) || !grepl("^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)*$", source_id) ||
      (!is.null(representation) && (!source_string(representation) || !representation %in% c("json", "csv", "html")))) {
    source_state_block("invalid_namespace")
  }
  invisible(TRUE)
}

# Lexical construction never consults directory existence: dots in the trusted
# configuration have the same meaning before and after mkdir. Relative content
# paths read from state still reject dots altogether in source_safe_path().
source_lexical_path <- function(path) {
  anchor <- if (grepl("^[A-Za-z]:/", path)) substr(path, 1L, 3L) else "/"
  parts <- strsplit(sub("^([A-Za-z]:)?/+", "", path), "/", fixed = TRUE)[[1]]
  stack <- character()
  for (part in parts) {
    if (!nzchar(part) || part == ".") next
    if (part == "..") {
      if (length(stack)) stack <- stack[-length(stack)]
    } else stack <- c(stack, part)
  }
  paste0(anchor, paste(stack, collapse = "/"))
}

# Identity uses an absolute lexical root, without normalizePath() or mkdir.
# Physical safety is checked separately via lstat-style Sys.readlink(): inspect
# the original path before cancelling dots, then every canonical ancestor.
# Symlink aliases are rejected, including one hidden by lexical cancellation.
source_operational_root <- function(config) {
  path <- config$data_dir
  if (!source_string(path) || grepl("[[:cntrl:]]", path)) source_state_block("invalid_data_directory")
  if (.Platform$OS.type == "windows") path <- gsub("\\", "/", path, fixed = TRUE)
  if (!grepl("^(/|[A-Za-z]:/)", path)) path <- file.path(getwd(), path)
  source_assert_no_links(path)
  root <- file.path(source_lexical_path(path), "cache", "sources")
  source_assert_no_links(root)
  root
}

# Reject every symlink in operational paths, including dangling links and
# aliases inside the root. This is deliberately stricter than containment.
source_assert_no_links <- function(path) {
  parents <- path
  while (!identical(dirname(path), path)) { path <- dirname(path); parents <- c(path, parents) }
  for (p in parents) {
    target <- Sys.readlink(p)
    if (length(target) == 1L && !is.na(target) && nzchar(target)) source_state_block("symlink_path")
  }
  invisible(TRUE)
}

source_safe_path <- function(root, relative) {
  if (!source_string(relative) || grepl("[\\\\:[:cntrl:]]", relative) || startsWith(relative, "/")) {
    source_state_block("unsafe_relative_path")
  }
  parts <- strsplit(relative, "/", fixed = TRUE)[[1]]
  if (any(!nzchar(parts)) || any(parts %in% c(".", "..")) || endsWith(relative, "/")) source_state_block("unsafe_relative_path")
  path <- do.call(file.path, as.list(c(root, parts)))
  source_assert_no_links(path)
  # The component checks above apply even to nonexistent parents.
  if (!startsWith(path, paste0(root, "/"))) source_state_block("path_outside_root")
  path
}

source_ensure_directory <- function(root, relative) {
  path <- source_safe_path(root, relative)
  if (!dir.exists(path)) {
    if (!dir.create(path, recursive = TRUE, showWarnings = FALSE, mode = "0700") && !dir.exists(path)) {
      source_state_block("directory_creation_failed")
    }
  }
  source_assert_no_links(path)
  if (!dir.exists(path)) source_state_block("not_directory")
  path
}

# POSIX test -f uses the actual stat file type without opening the object.
# R's utils::file_test("-f") only excludes directories and accepts FIFOs.
# Pass the path as a quoted positional argument to a constant shell program;
# consume only its exit status, never locale-dependent stat/ls output. No new
# package dependency is needed. Unsupported platforms or failed inspection
# return unknown, which the shared guard rejects before any read/hash.
source_file_is_regular <- function(path, platform = .Platform$OS.type, shell = Sys.which("sh")) {
  if (!identical(platform, "unix") || !source_string(shell)) return(NA)
  arguments <- c("-c", shQuote('test -f "$1"'), "source-file-type", shQuote(path))
  status <- tryCatch(system2(shell, arguments,
    stdout = FALSE, stderr = FALSE), warning = function(w) NA_integer_, error = function(e) NA_integer_)
  if (identical(status, 0L)) TRUE else if (identical(status, 1L)) FALSE else NA
}

source_require_regular_file <- function(path, code) {
  source_assert_no_links(path)
  if (!identical(source_file_is_regular(path), TRUE)) source_state_block(code)
  invisible(TRUE)
}

source_read_json <- function(path) {
  source_require_regular_file(path, "not_regular_json_file")
  tryCatch(jsonlite::parse_json(paste(readLines(path, encoding = "UTF-8", warn = FALSE), collapse = "\n"),
    simplifyVector = FALSE), error = function(e) source_state_block("invalid_json"))
}

source_write_json <- function(x, path) {
  con <- file(path, "wb")
  on.exit(close(con), add = TRUE)
  writeBin(charToRaw(paste0(source_canonical_json(x), "\n")), con)
  invisible(NULL)
}

source_failure_hook <- function(hooks, point, context) {
  if (!is.null(hooks[[point]])) hooks[[point]](context)
  invisible(NULL)
}

source_atomic_file <- function(root, relative, write, validate, hooks = list(), before_promote = function() NULL) {
  parent <- source_ensure_directory(root, dirname(relative))
  destination <- source_safe_path(root, relative)
  if (file.exists(destination)) source_state_block("destination_exists")
  temporary <- tempfile(".pending-", tmpdir = parent)
  context <- list(temporary = temporary, destination = destination)
  source_failure_hook(hooks, "before_temp_write", context)
  source_assert_no_links(temporary)
  if (file.exists(temporary)) source_state_block("temporary_exists")
  write(temporary)
  source_failure_hook(hooks, "after_temp_write", context)
  validate(temporary)
  source_failure_hook(hooks, "before_rename", context)
  before_promote()
  source_safe_path(root, relative)
  source_assert_no_links(temporary)
  if (file.exists(destination)) source_state_block("destination_exists")
  if (!file.rename(temporary, destination)) source_state_block("rename_failed")
  source_failure_hook(hooks, "after_rename", context)
  validate(source_safe_path(root, relative))
  destination
}

source_validate_lock_owner <- function(owner) {
  source_state_object(owner, c("token", "pid", "hostname", "started_at"))
  if (!source_state_token(owner$token) || !source_state_integer(owner$pid, 1) ||
      !source_string(owner$hostname) || !source_state_time(owner$started_at)) source_state_block("invalid_lock_owner")
  invisible(TRUE)
}

acquire_source_lock <- function(config, source_id, clock = source_state_now, id = source_state_id) {
  source_state_namespace(source_id)
  root <- source_operational_root(config)
  source_ensure_directory(root, "locks")
  relative <- paste0("locks/", source_id, ".lock")
  path <- source_safe_path(root, relative)
  if (!dir.create(path, showWarnings = FALSE, mode = "0700")) source_state_block("lock_busy")
  owner <- list(token = id(), pid = Sys.getpid(), hostname = unname(Sys.info()[["nodename"]]), started_at = clock())
  source_validate_lock_owner(owner)
  source_atomic_file(root, paste0(relative, "/owner.json"), function(p) source_write_json(owner, p),
    function(p) source_validate_lock_owner(source_read_json(p)))
  list(root = root, source_id = source_id, owner = owner)
}

assert_source_lock <- function(config, source_id, lock) {
  source_state_namespace(source_id)
  root <- source_operational_root(config)
  if (!is.list(lock) || !identical(lock$root, root) || !identical(lock$source_id, source_id)) source_state_block("lock_identity_mismatch")
  source_validate_lock_owner(lock$owner)
  path <- source_safe_path(root, paste0("locks/", source_id, ".lock/owner.json"))
  owner <- source_read_json(path)
  source_validate_lock_owner(owner)
  if (!identical(source_canonical_json(owner), source_canonical_json(lock$owner)) || owner$pid != Sys.getpid()) {
    source_state_block("lock_not_owned")
  }
  invisible(TRUE)
}

release_source_lock <- function(config, lock) {
  assert_source_lock(config, lock$source_id, lock)
  path <- source_safe_path(lock$root, paste0("locks/", lock$source_id, ".lock"))
  if (!identical(list.files(path, all.files = TRUE, no.. = TRUE), "owner.json")) source_state_block("unexpected_lock_files")
  # Only the verified, currently owned lock is removed. Orphans are never swept.
  if (unlink(path, recursive = TRUE) != 0L || dir.exists(path)) source_state_block("lock_release_failed")
  invisible(TRUE)
}

with_source_lock <- function(config, source_id, action, lock = NULL, clock = source_state_now, id = source_state_id) {
  owned <- is.null(lock)
  if (owned) lock <- acquire_source_lock(config, source_id, clock, id)
  if (owned) on.exit(release_source_lock(config, lock), add = TRUE)
  assert_source_lock(config, source_id, lock)
  action(lock)
}

source_content_relative <- function(source_id, representation, sha256) {
  source_state_namespace(source_id, representation)
  if (!source_state_hash(sha256)) source_state_block("invalid_content_hash")
  paste0("content/", source_id, "/", representation, "/", sha256, ".bin")
}

validate_source_content_reference <- function(content, source_id, representation) {
  if (!is.list(content) || any(!c("sha256", "bytes", "relative_path") %in% names(content)) ||
      !source_state_hash(content$sha256) || !source_state_integer(content$bytes, maximum = 2^53 - 1) ||
      !identical(content$relative_path, source_content_relative(source_id, representation, content$sha256))) {
    source_state_block("invalid_content_reference")
  }
  invisible(TRUE)
}

# Only this filesystem primitive is guarded: reference validation and subsequent
# logic stay outside the handler. The caller already supplies a safe scalar path.
source_content_file_info <- function(path, stat_file = function(p) file.info(p, extra_cols = FALSE)) {
  tryCatch(stat_file(path),
    warning = function(w) source_state_block("content_unreadable"),
    error = function(e) source_state_block("content_unreadable"))
}

source_content_file_hash <- function(path) {
  # digest's file prechecks/native fopen expose simpleError, without an errno
  # class. Recognize only their exact file-I/O diagnostics for this very path.
  # These messages are never returned/persisted or used as a logical error ID.
  io_messages <- paste0(c("The file does not exist: ", "The specified pathname is not a file: ",
    "The specified file is not readable: ", "Cannot open input file: "), path)
  tryCatch(sha256_file(path), error = function(e) {
    if (inherits(e, "simpleError") && conditionMessage(e) %in% io_messages) source_state_block("content_unreadable")
    stop(e) # Unknown errors, including programming defects, remain visible.
  })
}

verify_source_content <- function(config, source_id, representation, content) {
  tryCatch({
    validate_source_content_reference(content, source_id, representation)
    path <- source_safe_path(source_operational_root(config), content$relative_path)
    if (!file.exists(path)) source_state_block("content_missing")
    source_require_regular_file(path, "content_not_regular")
    info <- source_content_file_info(path)
    if (length(info$isdir) != 1L || is.na(info$isdir) ||
        !source_state_integer(info$size, maximum = 2^53 - 1)) source_state_block("content_unreadable")
    if (file.access(path, 4L) != 0L) source_state_block("content_unreadable")
    if (info$size != content$bytes) source_state_block("content_size_mismatch")
    if (!identical(source_content_file_hash(path), content$sha256)) source_state_block("content_hash_mismatch")
    list(valid = TRUE, decision = "allow", code = "verified", relative_path = content$relative_path,
      sha256 = content$sha256, bytes = content$bytes)
  }, source_state_block = function(e) list(valid = FALSE, decision = "block", code = e$code))
}

source_require_content <- function(config, source_id, representation, content) {
  result <- verify_source_content(config, source_id, representation, content)
  if (!result$valid) source_state_block(result$code)
  invisible(TRUE)
}

store_source_content <- function(config, source_id, representation, bytes, lock = NULL,
                                 hooks = list(), clock = source_state_now, id = source_state_id) {
  source_state_namespace(source_id, representation)
  if (!is.raw(bytes)) source_state_block("content_must_be_raw")
  with_source_lock(config, source_id, function(held) {
    root <- source_operational_root(config)
    sha <- digest::digest(bytes, algo = "sha256", serialize = FALSE)
    content <- list(sha256 = sha, bytes = length(bytes), relative_path = source_content_relative(source_id, representation, sha))
    path <- source_safe_path(root, content$relative_path)
    if (file.exists(path)) {
      source_require_content(config, source_id, representation, content)
      return(list(content = content, reused = TRUE))
    }
    source_atomic_file(root, content$relative_path, function(p) {
      con <- file(p, "wb"); on.exit(close(con), add = TRUE); writeBin(bytes, con)
    }, function(p) {
      source_require_regular_file(p, "content_not_regular")
      if (file.info(p)$size != content$bytes || !identical(sha256_file(p), sha)) source_state_block("blob_write_integrity")
    }, hooks, function() assert_source_lock(config, source_id, held))
    source_require_content(config, source_id, representation, content)
    list(content = content, reused = FALSE)
  }, lock, clock, id)
}

source_validation_metadata <- function(validation, accepted = FALSE) {
  fields <- c("decision", "classification", "contract_id", "contract_version", "contract_sha256", "kind",
    "evidence", "profile", "fingerprint", "pair_evidence")
  source_state_object(validation, fields, c("decision", "classification"))
  if (!source_string(validation$decision) || !validation$decision %in% c("allow", "warn", "block") ||
      !source_string(validation$classification) || !grepl("^[a-z_]+$", validation$classification) ||
      (accepted && validation$decision == "block")) source_state_block("invalid_content_validation")
  # No payload/table/message slots. Detailed schema evidence remains structural.
  source_canonical_json(validation)
  invisible(TRUE)
}

new_source_state <- function(identity, registry_revision_seen = NULL) {
  validate_source_request_identity(identity)
  d <- identity$descriptor
  list(state_schema_version = 1L, state_revision = 0L, source_id = d$source_id, representation = d$representation,
    request_identity = identity, registry_revision_seen = registry_revision_seen, last_check = NULL,
    last_http_observation = NULL, validated_content = NULL, latest_candidate = NULL, last_error = NULL,
    last_confirmed_content_change = NULL)
}

validate_source_state <- function(state, identity) {
  fields <- c("state_schema_version", "state_revision", "source_id", "representation", "request_identity",
    "registry_revision_seen", "last_check", "last_http_observation", "validated_content", "latest_candidate",
    "last_error", "last_confirmed_content_change")
  source_state_object(state, fields)
  tryCatch(validate_source_request_identity(identity), error = function(e) source_state_block("invalid_request_identity"))
  tryCatch(validate_source_request_identity(state$request_identity), error = function(e) source_state_block("invalid_state_identity"))
  if (!source_state_integer(state$state_schema_version, 1, 1) || !source_state_integer(state$state_revision)) source_state_block("invalid_state_version_revision")
  if (!identical(state$source_id, identity$descriptor$source_id) || !identical(state$representation, identity$descriptor$representation) ||
      !identical(source_canonical_json(state$request_identity), source_canonical_json(identity))) source_state_block("state_identity_mismatch")
  if (!is.null(state$registry_revision_seen) && !source_string(state$registry_revision_seen)) source_state_block("invalid_registry_revision")
  metadata <- list(last_check = c("check_id", "started_at", "finished_at", "status", "reason_codes"),
    last_http_observation = c("observed_at", "method", "request_url", "http_status", "etag_raw", "last_modified_raw", "event_id"),
    last_error = c("observed_at", "code", "kind", "resolved_at"),
    last_confirmed_content_change = c("observed_at", "previous_sha256", "observed_sha256", "candidate_accepted", "event_id"))
  for (field in names(metadata)) if (!is.null(state[[field]])) source_state_object(state[[field]], metadata[[field]], character())
  for (field in c("validated_content", "latest_candidate")) {
    content <- state[[field]]
    if (is.null(content)) next
    base <- c("sha256", "bytes", "relative_path", "validation")
    allowed <- if (field == "latest_candidate") c(base, "stored_at") else c(base, "retrieved_at", "validated_at",
      "etag_raw", "last_modified_raw", "conditional_reuse_allowed", "conditional_reuse_restrictions")
    source_state_object(content, allowed)
    validate_source_content_reference(content, state$source_id, state$representation)
    if (field == "latest_candidate") {
      if (!source_state_time(content$stored_at)) source_state_block("invalid_candidate_time")
      if (!is.null(content$validation)) source_validation_metadata(content$validation)
    } else {
      if (!source_state_time(content$retrieved_at) || !source_state_time(content$validated_at) ||
          !is.logical(content$conditional_reuse_allowed) || length(content$conditional_reuse_allowed) != 1L ||
          is.na(content$conditional_reuse_allowed) || !is.list(content$conditional_reuse_restrictions) ||
          any(!vapply(content$conditional_reuse_restrictions, source_string, logical(1)))) source_state_block("invalid_validated_metadata")
      for (key in c("etag_raw", "last_modified_raw")) if (!is.null(content[[key]]) && !source_string(content[[key]])) source_state_block("invalid_raw_validator_metadata")
      source_validation_metadata(content$validation, accepted = TRUE)
    }
  }
  tryCatch(source_canonical_json(state), error = function(e) source_state_block("invalid_canonical_state"))
  invisible(TRUE)
}

source_state_candidate <- function(state, content, validation = NULL, clock = source_state_now) {
  validate_source_state(state, state$request_identity)
  validate_source_content_reference(content, state$source_id, state$representation)
  if (!is.null(validation)) source_validation_metadata(validation)
  state$latest_candidate <- c(content[c("sha256", "bytes", "relative_path")], list(stored_at = clock(), validation = validation))
  validate_source_state(state, state$request_identity)
  state
}

source_state_promote <- function(state, validation, clock = source_state_now) {
  validate_source_state(state, state$request_identity)
  source_validation_metadata(validation, accepted = TRUE)
  candidate <- state$latest_candidate
  if (is.null(candidate)) source_state_block("no_candidate_to_promote")
  state$latest_candidate$validation <- validation
  state$validated_content <- c(candidate[c("sha256", "bytes", "relative_path")], list(retrieved_at = candidate$stored_at,
    validated_at = clock(), etag_raw = NULL, last_modified_raw = NULL, conditional_reuse_allowed = FALSE,
    conditional_reuse_restrictions = list("http_policy_not_implemented"), validation = validation))
  validate_source_state(state, state$request_identity)
  state
}

source_state_event <- function(type, identity, clock = source_state_now, id = source_state_id,
                               content_sha256 = NULL, decision = NULL, code = NULL, check_id = NULL) {
  validate_source_request_identity(identity)
  event <- list(event_schema_version = 1L, event_id = id(), type = type, occurred_at = clock(),
    source_id = identity$descriptor$source_id, representation = identity$descriptor$representation,
    request_identity_sha256 = identity$sha256, content_sha256 = content_sha256, decision = decision, code = code, check_id = check_id)
  validate_source_event(event, identity)
  event
}

validate_source_event <- function(event, identity) {
  source_state_object(event, c("event_schema_version", "event_id", "type", "occurred_at", "source_id", "representation",
    "request_identity_sha256", "content_sha256", "decision", "code", "check_id"))
  if (!source_state_integer(event$event_schema_version, 1, 1) || !source_state_token(event$event_id) ||
      !source_state_time(event$occurred_at) || !source_string(event$type) ||
      !event$type %in% c("state_initialized", "candidate_stored", "content_validated", "state_validation_failed",
        "check_started", "request_started", "request_finished", "check_finished") ||
      !identical(event$source_id, identity$descriptor$source_id) || !identical(event$representation, identity$descriptor$representation) ||
      !identical(event$request_identity_sha256, identity$sha256)) source_state_block("invalid_event")
  if (!is.null(event$content_sha256) && !source_state_hash(event$content_sha256)) source_state_block("invalid_event_hash")
  if (!is.null(event$decision) && !event$decision %in% c("allow", "warn", "block")) source_state_block("invalid_event_decision")
  if (!is.null(event$code) && (!source_string(event$code) || !grepl("^[a-z][a-z0-9_.-]*$", event$code))) source_state_block("invalid_event_code")
  if (!is.null(event$check_id) && !source_state_token(event$check_id)) source_state_block("invalid_check_id")
  invisible(TRUE)
}

source_record_checksum <- function(record) {
  tryCatch(source_canonical_sha256(record[setdiff(names(record), "record_sha256")]),
    error = function(e) source_state_block("invalid_canonical_record"))
}

validate_source_record <- function(record, identity, revision, previous_sha256) {
  source_state_object(record, c("record_schema_version", "state_revision", "previous_record_sha256", "record_sha256", "event", "state_after"))
  if (!source_state_integer(record$record_schema_version, 1, 1) || !source_state_integer(record$state_revision, 1) ||
      record$state_revision != revision || !identical(record$previous_record_sha256, previous_sha256) ||
      !source_state_hash(record$record_sha256) || !identical(record$record_sha256, source_record_checksum(record))) source_state_block("invalid_revision_checksum_chain")
  validate_source_state(record$state_after, identity)
  if (record$state_after$state_revision != revision) source_state_block("state_revision_mismatch")
  validate_source_event(record$event, identity)
  invisible(TRUE)
}

source_revisions_relative <- function(identity) {
  validate_source_request_identity(identity)
  paste0("state/", identity$descriptor$source_id, "/", identity$descriptor$representation, "/", identity$sha256, "/revisions")
}

# Pure inspection, including a list_entries injection for offline failure tests.
# A failed stat can mean an unsearchable ancestor rather than absence: establish
# access to the nearest existing parent before returning state_absent. For an
# existing directory, both read and search permission are required, before and
# after listing. Warnings/errors never serve as evidence of an empty history.
source_revision_listing <- function(path, list_entries = function(p) list.files(p, all.files = TRUE, no.. = TRUE)) {
  probe <- path
  while (!file.exists(probe)) {
    parent <- dirname(probe)
    if (identical(parent, probe)) source_state_block("revisions_unreadable")
    probe <- parent
  }
  if (!dir.exists(probe)) source_state_block("revisions_not_directory")
  accessible <- function(p) dir.exists(p) && file.access(p, 4L) == 0L && file.access(p, 1L) == 0L
  if (!accessible(probe)) source_state_block("revisions_unreadable")
  if (!identical(probe, path)) return(list(status = "state_absent", entries = character()))
  entries <- tryCatch(list_entries(path),
    warning = function(w) source_state_block("revisions_unreadable"),
    error = function(e) source_state_block("revisions_unreadable"))
  if (!accessible(path) || !is.character(entries) || anyNA(entries) || anyDuplicated(entries)) {
    source_state_block("revisions_unreadable")
  }
  list(status = if (length(entries)) "revisions_available" else "revisions_empty", entries = entries)
}

read_source_revisions <- function(config, identity) {
  root <- source_operational_root(config)
  relative <- source_revisions_relative(identity)
  path <- source_safe_path(root, relative)
  entries <- source_revision_listing(path)$entries
  # Unpromoted temporary files are evidence, never revisions or repair inputs.
  entries <- entries[!startsWith(entries, ".pending-")]
  if (any(!grepl("^[0-9]{12}\\.json$", entries))) source_state_block("invalid_revision_filename")
  entries <- sort(entries, method = "radix")
  if (!identical(as.numeric(substr(entries, 1L, 12L)), as.numeric(seq_along(entries)))) source_state_block("revision_gap")
  records <- list(); previous <- NULL; event_ids <- character()
  for (i in seq_along(entries)) {
    record <- source_read_json(source_safe_path(root, paste0(relative, "/", entries[i])))
    validate_source_record(record, identity, i, previous)
    if (record$event$event_id %in% event_ids) source_state_block("duplicate_event_id")
    event_ids <- c(event_ids, record$event$event_id)
    previous <- record$record_sha256; records[[i]] <- record
  }
  records
}

read_source_state <- function(config, identity) {
  records <- read_source_revisions(config, identity)
  if (!length(records)) return(NULL)
  state <- records[[length(records)]]$state_after
  for (field in c("latest_candidate", "validated_content")) if (!is.null(state[[field]])) {
    source_safe_path(source_operational_root(config), state[[field]]$relative_path)
  }
  if (!is.null(state$validated_content)) source_require_content(config, state$source_id, state$representation, state$validated_content)
  state
}

commit_source_event <- function(config, identity, event, state_after, lock = NULL,
                                hooks = list(), clock = source_state_now, id = source_state_id) {
  validate_source_state(state_after, identity)
  validate_source_event(event, identity)
  with_source_lock(config, identity$descriptor$source_id, function(held) {
    records <- read_source_revisions(config, identity)
    previous <- if (length(records)) records[[length(records)]] else NULL
    if (state_after$state_revision != length(records)) source_state_block("stale_state_revision")
    if (event$event_id %in% vapply(records, function(r) r$event$event_id, character(1))) source_state_block("duplicate_event_id")
    old_content <- if (is.null(previous)) NULL else previous$state_after$validated_content
    if (!identical(source_canonical_json(old_content), source_canonical_json(state_after$validated_content)) &&
        (event$type != "content_validated" || is.null(state_after$validated_content) ||
          !identical(event$content_sha256, state_after$validated_content$sha256))) source_state_block("implicit_validated_transition")
    for (field in c("validated_content", "latest_candidate")) if (!is.null(state_after[[field]])) {
      source_require_content(config, state_after$source_id, state_after$representation, state_after[[field]])
    }
    revision <- length(records) + 1L
    state_after$state_revision <- revision
    record <- list(record_schema_version = 1L, state_revision = revision,
      previous_record_sha256 = if (is.null(previous)) NULL else previous$record_sha256,
      record_sha256 = NULL, event = event, state_after = state_after)
    record$record_sha256 <- source_record_checksum(record)
    relative <- paste0(source_revisions_relative(identity), "/", sprintf("%012d.json", revision))
    validate <- function(path) {
      actual <- source_read_json(path)
      validate_source_record(actual, identity, revision, record$previous_record_sha256)
      if (!identical(source_canonical_json(actual), source_canonical_json(record))) source_state_block("revision_roundtrip_mismatch")
    }
    source_atomic_file(source_operational_root(config), relative, function(p) source_write_json(record, p), validate,
      hooks, function() assert_source_lock(config, state_after$source_id, held))
    read_source_state(config, identity)
  }, lock, clock, id)
}
