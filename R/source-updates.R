# Checkpoint 1B, step III, unit A: pure internal decisions on supplied evidence.
# No clock, registry resolution, transport, state access or content promotion.
source_update_abort <- function(code) {
  stop(structure(list(message = paste0("Source update argument: ", code), call = NULL, code = code),
    class = c("source_update_argument_error", "error", "condition")))
}

source_update_statuses <- function() {
  c("initialized", "content_unchanged", "content_changed", "not_modified", "metadata_changed",
    "indeterminate", "incompatible_content", "source_unavailable", "check_failed", "blocked")
}

source_update_flag <- function(x, unknown = FALSE) {
  is.logical(x) && length(x) == 1L && is.null(attributes(x)) && (unknown || !is.na(x))
}

source_update_object <- function(x, allowed, required = character(), project = FALSE) {
  if (!is.list(x) || is.data.frame(x) || (length(x) && is.null(names(x))) ||
      anyNA(names(x)) || anyDuplicated(names(x)) || any(!nzchar(names(x))) ||
      any(!required %in% names(x)) || (!project && any(!names(x) %in% allowed))) {
    source_update_abort("invalid_evidence_fields")
  }
  x <- unclass(x)
  x[intersect(names(x), allowed)]
}

# Observations contain an effective identity SHA, a method, and raw validator
# headers. Invalid/duplicate headers remain unknown, never comparable absence.
# URL spelling and redirects are intentionally not inputs to this comparison.
source_update_compare_metadata <- function(previous, current) {
  observation <- function(x) {
    if (is.null(x)) return(NULL)
    x <- source_update_object(x, c("identity_sha256", "method", "headers"))
    if (!source_state_hash(x$identity_sha256) || !source_string(x$method) ||
        !x$method %in% c("HEAD", "GET") || !is.list(x$headers) ||
        (length(x$headers) && (is.null(names(x$headers)) || anyNA(names(x$headers)) ||
          any(!nzchar(names(x$headers)))))) return(NULL)
    validators <- source_http_validators(x$headers)
    if (length(validators$invalid)) return(NULL)
    list(identity = x$identity_sha256, method = x$method,
      values = validators[c("etag_raw", "last_modified_raw")])
  }
  before <- observation(previous); after <- observation(current)
  if (is.null(before) || is.null(after) || !identical(before$identity, after$identity) ||
      !identical(before$method, after$method)) return(NA)
  present <- function(x) !vapply(x$values, is.null, logical(1))
  keys <- present(before)
  if (!any(keys) || !identical(keys, present(after))) return(NA)
  !identical(before$values[keys], after$values[keys])
}

# Minimal byte evidence; no paths, payloads or scientific record values.
source_update_content_evidence <- function(x) {
  if (is.null(x)) return(NULL)
  x <- source_update_object(x, c("identity_sha256", "sha256"), c("identity_sha256", "sha256"))
  if (!all(vapply(x, source_state_hash, logical(1)))) source_update_abort("invalid_content_evidence")
  x
}

source_update_result <- function(status, content_changed = switch(status,
                                   content_unchanged = FALSE, content_changed = TRUE, NA),
                                 metadata_changed = NA, redirected = FALSE,
                                 severity = NULL, retryable = FALSE, reason_codes = character(),
                                 baseline = NULL, candidate = NULL, validation = NULL, error = NULL) {
  if (!source_string(status) || !status %in% source_update_statuses()) source_update_abort("invalid_status")
  expected <- switch(status, content_unchanged = FALSE, content_changed = TRUE, NA)
  if (!source_update_flag(content_changed, TRUE) || !identical(content_changed, expected) ||
      !source_update_flag(metadata_changed, TRUE) || !source_update_flag(redirected) ||
      !source_update_flag(retryable)) source_update_abort("invalid_result_flags")
  if ((status == "metadata_changed" && !isTRUE(metadata_changed)) ||
      (status == "indeterminate" && isTRUE(metadata_changed))) source_update_abort("contradictory_metadata_status")
  if (!is.character(reason_codes) || anyNA(reason_codes) || anyDuplicated(reason_codes) ||
      any(!grepl("^[a-z][a-z0-9_.-]*$", reason_codes)) || !is.null(attributes(reason_codes))) {
    source_update_abort("invalid_reason_codes")
  }
  failure <- status %in% c("incompatible_content", "source_unavailable", "check_failed", "blocked")
  if (is.null(severity)) severity <- if (failure) "error" else "normal"
  allowed <- if (failure) "error" else if (status == "indeterminate") c("normal", "warning") else "normal"
  if (!source_string(severity) || !severity %in% allowed ||
      (severity == "warning" && !length(reason_codes))) source_update_abort("invalid_severity")
  if (retryable && (!status %in% c("source_unavailable", "check_failed", "blocked") ||
      !length(reason_codes) || any(reason_codes %in% c("http_404", "state_corrupt", "protocol_error", "tls_trust_failure")))) {
    source_update_abort("invalid_retryability")
  }
  baseline <- source_update_content_evidence(baseline)
  candidate <- source_update_content_evidence(candidate)
  if (status %in% c("initialized", "content_unchanged", "content_changed") && is.null(candidate)) {
    source_update_abort("missing_candidate_evidence")
  }
  if (status %in% c("content_unchanged", "content_changed", "not_modified") && is.null(baseline)) {
    source_update_abort("missing_baseline_evidence")
  }
  if (status == "initialized" && !is.null(baseline)) source_update_abort("initialized_with_baseline")
  if (!is.null(baseline) && !is.null(candidate)) {
    if (!identical(baseline$identity_sha256, candidate$identity_sha256)) source_update_abort("different_content_identities")
    if (status %in% c("content_unchanged", "content_changed") &&
        !identical(content_changed, baseline$sha256 != candidate$sha256)) source_update_abort("contradictory_content_hashes")
  }
  if (status %in% c("not_modified", "metadata_changed") && !is.null(candidate)) source_update_abort("unexpected_candidate")
  if (!is.null(validation)) validation <- source_update_validation_metadata(validation,
    accepted = status %in% c("initialized", "content_unchanged", "content_changed", "not_modified"))
  if (!is.null(error)) {
    error <- source_update_object(error, c("kind", "code"), c("kind", "code"))
    if (!failure || !all(vapply(error, function(x) source_string(x) &&
        grepl("^[a-z][a-z0-9_.-]*$", x), logical(1)))) source_update_abort("invalid_error_evidence")
  }
  list(result_version = 1L, status = status, content_changed = content_changed,
    metadata_changed = metadata_changed, severity = severity, reason_codes = reason_codes,
    retryable = retryable, redirected = redirected, transport = NULL, baseline = baseline,
    validation = validation, candidate = candidate, persistence = NULL, error = error)
}

# One representation, one explicitly observed outcome. Mutually exclusive facts
# cannot be silently combined; multi-representation precedence belongs to unit C.
# accepted_304 means the caller has already established legitimate reuse and
# revalidation. This function neither trusts arbitrary HTTP 304s nor reads cache.
source_update_classify_representation <- function(observation, identity_sha256 = NULL,
                                                 content_sha256 = NULL, baseline = NULL,
                                                 metadata_changed = NA, redirected = FALSE,
                                                 reason_codes = character(), retryable = FALSE,
                                                 severity = NULL) {
  allowed <- c("accepted_200", "accepted_304", "head", "incompatible_content",
    "source_unavailable", "check_failed", "blocked", "indeterminate")
  if (!source_string(observation) || !observation %in% allowed) source_update_abort("invalid_observation")
  baseline <- source_update_content_evidence(baseline)
  if (!is.null(identity_sha256) && !source_state_hash(identity_sha256)) source_update_abort("invalid_identity_hash")
  if (!is.null(baseline) && !identical(baseline$identity_sha256, identity_sha256)) source_update_abort("different_content_identities")
  accepted <- observation %in% c("accepted_200", "accepted_304")
  if (accepted && !source_state_hash(identity_sha256)) source_update_abort("missing_content_identity")
  if (!is.null(content_sha256) && observation != "accepted_200") source_update_abort("unexpected_content_hash")
  candidate <- NULL
  status <- observation
  if (observation == "accepted_200") {
    if (!source_state_hash(content_sha256)) source_update_abort("invalid_content_hash")
    candidate <- list(identity_sha256 = identity_sha256, sha256 = content_sha256)
    status <- if (is.null(baseline)) "initialized" else
      if (identical(baseline$sha256, content_sha256)) "content_unchanged" else "content_changed"
  } else if (observation == "accepted_304") {
    if (is.null(baseline)) source_update_abort("missing_304_baseline")
    status <- "not_modified"
  } else if (observation == "head") {
    status <- if (isTRUE(metadata_changed)) "metadata_changed" else "indeterminate"
  }
  source_update_result(status, metadata_changed = metadata_changed, redirected = redirected,
    baseline = baseline, candidate = candidate, reason_codes = reason_codes, retryable = retryable, severity = severity)
}

# Only these structural shapes may cross into persistent validation metadata.
# Unknown fields are projected out at EVERY object level, not just at the root.
# The fingerprint's opaque `canonical` JSON string is intentionally not copied:
# structural profiles, quality, unknown paths and both hashes remain available.
source_update_validation_shape <- function() {
  changes <- list(path = "path", code = "code", expected = "structural_text", observed = "structural_text",
    severity = "drift")
  partner <- list(representation = "representation", requested_identity_sha256 = "hash",
    effective_identity_sha256 = "hash", content_sha256 = "hash", event_id = "token", state_revision = "count")
  list(decision = "decision", classification = "code", contract_id = "code", contract_version = "count",
    contract_sha256 = "hash", kind = "code",
    evidence = list(quality = "quality", record_count = "count", observed_paths = "count", unknown_paths = "paths",
      changes = list(.records = changes, .dataframe = TRUE)),
    profile = list(profile_version = "count", nodes = list(.records = list(path = "path", types = "types",
      observations = "count", nulls = "count", object_observations = "count"))),
    fingerprint = list(sha256 = "hash", observed_sha256 = "hash", evidence_quality = "quality", unknown_paths = "paths"),
    pair_evidence = list(check_id = "token", representation = "representation", requested_identity_sha256 = "hash",
      effective_identity_sha256 = "hash", content_sha256 = "hash", partner = partner, classification = "code",
      decision = "decision", contract_id = "code", contract_version = "count", contract_sha256 = "hash",
      registry_revision = "code", event_id = "token", state_revision = "count",
      comparison = list(json_records = "count", csv_records = "count", projection_lossy = "boolean",
        compared_fields = "strings", unsupported_fields = "strings", divergent_fields = "strings",
        row_multiset_matches = "boolean", comparison_coverage = list(total_fields = "count",
          compared_fields = "count", unsupported_fields = "count"), issues = "codes", source_classification = "code")))
}

source_update_structural_value <- function(x, type) {
  if (is.null(x)) return(NULL)
  if (is.factor(x)) x <- as.character(x)
  vector_types <- c(strings = "string", paths = "path", types = "node_type", codes = "code")
  if (type %in% names(vector_types)) {
    if ((!is.character(x) && !is.list(x)) || !is.null(names(x))) source_update_abort("invalid_structural_vector")
    return(lapply(x, source_update_structural_value, type = vector_types[[type]]))
  }
  if (!is.atomic(x) || is.raw(x) || is.complex(x)) source_update_abort("invalid_structural_value")
  attributes(x) <- NULL
  if (is.numeric(x) && any(is.nan(x) | is.infinite(x))) source_update_abort("nonfinite_structural_value")
  if (length(x) != 1L) source_update_abort("invalid_structural_scalar")
  if (is.na(x)) return(NULL)
  text <- is.character(x) && nzchar(x) && !grepl("[[:cntrl:]]", x)
  node_types <- c("object", "array", "string", "number", "boolean", "null", "unsupported")
  structural_text <- c("present in every parent", "absent in some or all parents", "non-null",
    "not declared", "additional structural field", "previously observed field", "absent",
    "JSON-compatible value", "unsupported R value", "unique nonempty keys", "ambiguous keys",
    "field present", "minimum items", "insufficient items", "minimum length", "too short",
    "declared structural pattern", "not matched")
  valid <- switch(type,
    string = is.character(x) && nzchar(x), # Structural field names, not record values.
    code = text && grepl("^[a-z0-9][a-z0-9_.-]*$", x),
    token = source_state_token(x),
    hash = source_state_hash(x),
    count = source_state_integer(x, maximum = 2^53 - 1),
    boolean = source_update_flag(x),
    # source_path() also describes invalid empty keys and escaped unusual keys.
    # Preserve these diagnostics; Canonical JSON escapes control characters.
    path = is.character(x) && grepl("^\\$(/[^/]*)*$", x),
    node_type = text && x %in% node_types,
    structural_text = text && (x %in% structural_text || all(strsplit(x, "|", fixed = TRUE)[[1]] %in% node_types)),
    decision = text && x %in% c("allow", "warn", "block"),
    drift = text && x %in% c("valid", "additive", "suspicious", "breaking", "insufficient_evidence"),
    quality = text && x %in% c("partial", "complete"),
    representation = text && x %in% c("json", "csv", "html"), FALSE)
  if (!isTRUE(valid)) source_update_abort("invalid_structural_value")
  x
}

source_update_project_structure <- function(x, shape) {
  if (is.character(shape)) return(source_update_structural_value(x, shape))
  if (is.null(x)) return(NULL)
  if (!is.null(shape$.records)) {
    if (is.data.frame(x)) {
      if (!isTRUE(shape$.dataframe) || anyNA(names(x)) || anyDuplicated(names(x))) source_update_abort("unexpected_structural_table")
      # Only the known changes table is converted, and only known columns.
      columns <- intersect(names(shape$.records), names(x))
      x <- lapply(seq_len(nrow(x)), function(i) lapply(x[columns], function(column) column[i]))
    }
    if (!is.list(x) || !is.null(names(x))) source_update_abort("invalid_structural_records")
    return(lapply(x, source_update_project_structure, shape = shape$.records))
  }
  x <- source_update_object(x, names(shape), project = TRUE)
  out <- lapply(names(x), function(key) source_update_project_structure(x[[key]], shape[[key]]))
  stats::setNames(out, names(x))
}

source_update_validation_metadata <- function(validation, accepted = FALSE) {
  if (!source_update_flag(accepted)) source_update_abort("invalid_accepted_flag")
  shape <- source_update_validation_shape()
  input <- source_update_object(validation, c(names(shape), "changes"),
    c("decision", "classification"), project = TRUE)
  if ("changes" %in% names(input)) {
    evidence <- input$evidence
    if (is.null(evidence)) evidence <- list()
    evidence <- source_update_object(evidence, names(shape$evidence), project = TRUE)
    if ("changes" %in% names(evidence)) source_update_abort("ambiguous_changes_evidence")
    evidence["changes"] <- list(input$changes)
    input["evidence"] <- list(evidence)
  }
  out <- source_update_project_structure(input, shape)
  if (accepted && identical(out$pair_evidence$decision, "block")) source_update_abort("blocked_pair_evidence")
  source_validation_metadata(out, accepted = accepted)
  out
}
