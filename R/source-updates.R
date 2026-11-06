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

# B1a observation boundary. The source_update_* core above remains pure.
# Only the existing transport may store a blob/use its cache lock. No checker
# state mutation, event, promotion, persistence lock or joint acceptance occurs.
source_observation_executor <- function(execute, record) {
  function(req, ...) {
    observe <- function(cnd) {
      cause <- if (inherits(cnd, "httr2_failure")) cnd$parent else cnd
      trust <- c("curl_error_peer_failed_verification", "curl_error_ssl_cacert_badfile",
        "curl_error_ssl_issuer_error", "curl_error_ssl_crl_badfile",
        "curl_error_ssl_pinnedpubkeynotmatch", "curl_error_ssl_invalidcertstatus")
      if (inherits(cause, "curl_error") && any(vapply(trust, function(cl) inherits(cause, cl), logical(1)))) {
        record("tls_trust_failure")
      }
      invisible(NULL) # Observe, then let the adapter handle the original condition.
    }
    withCallingHandlers(execute(req, ...), httr2_failure = observe, curl_error = observe)
  }
}

source_observation_load_baseline <- function(config, identity, state_lookup = source_http_state_lookup) {
  state <- state_lookup(config, identity)
  if (!is.null(state)) validate_source_state(state, identity)
  # Missing/invalid blobs disable conditions in the transport. A valid revision
  # still supplies the historical accepted hash for a subsequent new retrieval.
  content <- state$validated_content
  list(state = state, baseline = if (is.null(content)) NULL else
    list(identity_sha256 = identity$sha256, sha256 = content$sha256))
}

source_observation_metadata <- function(state, identity, method, headers, policy) {
  if ("last_http_invalid_validator" %in% state$last_check$reason_codes) return(NA)
  old <- state$last_http_observation
  previous <- NULL
  if (!is.null(old) && source_state_time(old$observed_at) &&
      source_state_integer(old$http_status, 200, 399) &&
      (old$http_status < 300L || old$http_status == 304L) &&
      source_http_urls_equivalent(identity$descriptor$absolute_request_url, old$request_url, policy)) {
    validators <- list(etag = old$etag_raw, `last-modified` = old$last_modified_raw)
    previous <- list(identity_sha256 = identity$sha256, method = old$method,
      headers = validators[!vapply(validators, is.null, logical(1))])
  }
  source_update_compare_metadata(previous,
    list(identity_sha256 = identity$sha256, method = method, headers = headers))
}

source_observation_validate <- function(config, identity, content, contract, reference = NULL,
                                        reader = read_source_payload, validator = validate_source_payload) {
  d <- identity$descriptor
  source_require_content(config, d$source_id, d$representation, content)
  path <- source_safe_path(source_operational_root(config), content$relative_path)
  # The 1A parser exposes these two fixed simpleError diagnostics, not a typed
  # parse condition. Recognize them only at the parser boundary; validator and
  # unexpected reader errors propagate. No message enters the observation.
  parsed <- tryCatch(list(payload = reader(path, d$representation)), simpleError = function(e) {
    expected <- switch(d$representation, json = "Invalid JSON structure.",
      csv = "Invalid CSV structure or parsing problems.", NULL)
    if (!is.null(expected) && identical(conditionMessage(e), expected)) return(list(invalid = TRUE))
    stop(e)
  })
  source_require_content(config, d$source_id, d$representation, content)
  complete <- d$representation != "csv"
  reason <- NULL
  if (isTRUE(parsed$invalid)) {
    validation <- list(decision = "block", classification = "breaking", kind = "syntax")
    reason <- "invalid_payload"
  } else if (!complete) {
    # CSV syntax and required columns can be inspected alone. Record values and
    # projected consistency require JSON from the same cycle (unit C).
    required <- names(Filter(function(x) isTRUE(x$required), source_records_schema(contract)$items$properties))
    missing <- setdiff(required, names(parsed$payload))
    validation <- list(decision = if (length(missing)) "block" else "allow",
      classification = if (length(missing)) "breaking" else "insufficient_evidence",
      kind = "csv_structure", evidence = list(quality = "partial", record_count = nrow(parsed$payload)))
    reason <- if (length(missing)) "csv_required_columns" else "csv_requires_json"
  } else {
    # Canonical persisted profiles have list-valued type arrays; restore the
    # in-memory shape expected by 1A without changing their structural meaning.
    if (!is.null(reference)) reference$nodes <- lapply(reference$nodes, function(node) {
      node$types <- unlist(node$types, use.names = FALSE); node
    })
    validation <- validator(parsed$payload, contract, source_id = d$source_id,
      representation = d$representation, reference = reference)
    validation$profile <- profile_source_schema(parsed$payload)
    validation$kind <- "schema"
    reason <- paste0("schema_", validation$classification)
  }
  validation$contract_id <- contract$contract_id
  validation$contract_version <- contract$version
  validation$contract_sha256 <- source_canonical_sha256(contract)
  list(validation = source_update_validation_metadata(validation), complete = complete, reason = reason)
}

source_observation_failure <- function(transport, evidence) {
  kind <- transport$error$kind; code <- transport$error$code
  retryable <- FALSE
  status <- switch(transport$outcome, blocked = "blocked", http_error = "source_unavailable",
    transport_error = "source_unavailable", protocol_error = "check_failed",
    redirect_error = "check_failed", argument_error = "check_failed", NULL)
  if (is.null(status)) source_update_abort("unknown_transport_outcome")
  if (transport$outcome == "http_error") {
    code <- paste0("http_", transport$http_status)
    retryable <- transport$http_status %in% c(429L, 500L, 502L, 503L, 504L)
  } else if (transport$outcome == "transport_error") {
    retryable <- isTRUE(evidence$retryable)
    if (identical(evidence$typed_code, "tls_trust_failure")) {
      status <- "check_failed"; code <- "tls_trust_failure"; retryable <- FALSE
    }
  } else if (transport$outcome == "blocked") retryable <- identical(code, "lock_busy")
  source_update_result(status, reason_codes = code, retryable = retryable,
    redirected = length(transport$redirects) > 0L, error = list(kind = kind, code = code))
}

# identity is supplied by the caller using source_request_identity(); URL discovery
# and logical-source orchestration are deliberately outside this boundary.
# NULL joint context defaults to pending for contracts declaring a CSV projection.
source_observation_representation <- function(config, identity, registry = load_source_registry(),
                                               allow_download = FALSE, force_content = FALSE,
                                               joint_acceptance_required = NULL,
                                               execute = httr2::req_perform,
                                               state_lookup = source_http_state_lookup,
                                               contract_loader = load_schema_contract,
                                               reader = read_source_payload, validator = validate_source_payload,
                                               clock = source_state_now, sleep = Sys.sleep) {
  if (!source_update_flag(allow_download) || !source_update_flag(force_content) ||
      (force_content && !allow_download)) source_update_abort("invalid_download_contract")
  validate_source_request_identity(identity)
  d <- identity$descriptor
  checked <- source_request_identity(d$source_id, d$representation, d$absolute_request_url, registry, d$request_headers)
  if (!identical(checked$sha256, identity$sha256)) source_update_abort("invalid_request_identity")
  source <- Filter(function(s) identical(s$source_id, d$source_id), registry$sources)[[1L]]
  contract <- contract_loader(source$representations[[d$representation]]$contract)
  validate_schema_contract(contract)
  if (!d$representation %in% contract$representations) source_update_abort("incompatible_contract")
  if (is.null(joint_acceptance_required)) joint_acceptance_required <- "csv" %in% contract$representations
  if (!source_update_flag(joint_acceptance_required) ||
      (d$representation == "csv" && !joint_acceptance_required)) source_update_abort("invalid_joint_context")
  started <- clock()
  if (!source_state_time(started)) source_update_abort("invalid_clock")
  states <- list(); terminal <- NULL; response_headers <- NULL; transport <- NULL
  effective <- identity
  lookup <- function(config, identity) {
    effective <<- identity
    loaded <- source_observation_load_baseline(config, identity, state_lookup)
    states[identity$sha256] <<- list(loaded)
    loaded$state
  }
  finish <- function(out, plan = NULL, content = NULL, retrieved_at = NULL) {
    ended <- clock()
    if (!source_state_time(ended)) source_update_abort("invalid_clock")
    # Inspect only the terminal response, before invalid headers become NULL.
    if (!is.null(response_headers) && length(source_http_validators(response_headers)$invalid)) {
      out$reason_codes <- unique(c(out$reason_codes, "last_http_invalid_validator"))
    }
    loaded <- states[[effective$sha256]]
    out["transport"] <- list(transport)
    out$context <- list(requested_identity = identity, effective_identity = effective,
      registry_revision = registry$registry_revision, contract_id = contract$contract_id,
      contract_version = contract$version, contract_sha256 = source_canonical_sha256(contract),
      state_revision = if (is.null(loaded$state)) NULL else loaded$state$state_revision,
      started_at = started, checked_at = ended)
    out$joint_acceptance_required <- joint_acceptance_required
    out["planned_event_type"] <- list(plan)
    out["content"] <- list(if (is.null(content)) NULL else
      c(content[c("sha256", "bytes", "relative_path")], list(retrieved_at = retrieved_at)))
    out
  }
  run <- function() {
    # Preflight also covers HEAD, whose transport intentionally does no state IO.
    initial <- lookup(config, identity)
    initial_pending <- TRUE
    take_state <- function(config, current) {
      if (initial_pending && identical(current$sha256, identity$sha256)) {
        initial_pending <<- FALSE
        return(initial)
      }
      lookup(config, current)
    }
    performer <- function(request) {
      # Reset before state lookup as well: a blocked destination has no response.
      terminal <<- NULL; response_headers <<- NULL
      if (request$method == "HEAD") take_state(config, request$identity)
      effective <<- request$identity
      typed <- NULL; converted <- NULL
      observed_execute <- source_observation_executor(execute, function(code) { typed <<- code })
      response <- withCallingHandlers(source_http_perform(request, execute = observed_execute),
        source_http_transport_error = function(e) {
          converted <<- list(code = e$code, retryable = isTRUE(e$retryable))
          terminal <<- c(list(identity_sha256 = request$identity$sha256, typed_code = typed), converted)
        })
      # Even a custom executor that internally recovered cannot leak old evidence.
      terminal <<- NULL
      response_headers <<- response$headers
      response
    }
    transport <<- source_http_request(config, identity, registry, allow_download = allow_download,
      force_content = force_content, performer = performer, state_lookup = take_state, clock = clock, sleep = sleep)
    effective <<- transport$identity
    last <- if (length(transport$requests)) transport$requests[[length(transport$requests)]] else NULL
    if (is.null(last) || !identical(last$identity_sha256, effective$sha256)) {
      # Keep intermediate responses in requests/redirects, never on the blocked target.
      transport[c("http_status", "observed_etag_raw", "observed_last_modified_raw", "condition")] <<- list(NULL, NULL, NULL, NULL)
      transport$condition_sent <<- FALSE
      terminal <<- NULL; response_headers <<- NULL
    }
    loaded <- states[[effective$sha256]]
    baseline <- loaded$baseline
    redirected <- length(transport$redirects) > 0L
    if (!transport$outcome %in% c("metadata", "candidate", "not_modified")) {
      out <- source_observation_failure(transport, terminal)
      return(finish(out, if (out$status == "blocked") NULL else "check_finished"))
    }
    metadata <- source_observation_metadata(loaded$state, effective, transport$method,
      response_headers, registry$url_policy)
    if (transport$outcome == "metadata") {
      return(finish(source_update_classify_representation("head", effective$sha256,
        baseline = baseline, metadata_changed = metadata, redirected = redirected), "check_finished"))
    }
    reused <- transport$outcome == "not_modified"
    content <- if (reused) transport$reused_content else transport$content
    retrieved <- if (reused) loaded$state$validated_content$retrieved_at else transport$retrieved_at
    if (reused && (is.null(baseline) || !identical(content$sha256, baseline$sha256))) {
      source_state_block("revalidation_baseline_mismatch")
    }
    checked <- source_observation_validate(config, effective, content, contract,
      reference = loaded$state$validated_content$validation$profile, reader = reader, validator = validator)
    validation <- checked$validation
    evidence <- list(identity_sha256 = effective$sha256, sha256 = content$sha256)
    if (validation$decision == "block") {
      out <- source_update_result("incompatible_content", metadata_changed = metadata,
        redirected = redirected, baseline = baseline, candidate = if (reused) NULL else evidence,
        validation = validation, reason_codes = checked$reason)
      return(finish(out, if (reused) "state_validation_failed" else "candidate_stored", content, retrieved))
    }
    if (joint_acceptance_required || !checked$complete) {
      # No accepted-byte classification before the caller's joint decision.
      # A proven metadata change remains reportable independently of that decision.
      out <- source_update_result(if (isTRUE(metadata)) "metadata_changed" else "indeterminate",
        metadata_changed = metadata, redirected = redirected, baseline = baseline,
        candidate = if (reused || isTRUE(metadata)) NULL else evidence, validation = validation,
        reason_codes = unique(c("joint_acceptance_pending", checked$reason)))
      return(finish(out, content = content, retrieved_at = retrieved))
    }
    out <- source_update_classify_representation(if (reused) "accepted_304" else "accepted_200",
      effective$sha256, content_sha256 = if (reused) NULL else content$sha256,
      baseline = baseline, metadata_changed = metadata, redirected = redirected, reason_codes = checked$reason)
    out$validation <- source_update_validation_metadata(validation, accepted = TRUE)
    finish(out, "content_validated", content, retrieved)
  }
  # Only the known integrity condition is translated here. Unexpected programming
  # failures (including reader/validator/executor bugs) keep propagating.
  tryCatch(run(), source_state_block = function(e) finish(source_update_result("blocked",
    reason_codes = e$code, error = list(kind = "state", code = e$code),
    redirected = !is.null(transport) && length(transport$redirects) > 0L)))
}

# B1b: terminal persistence only. Observations and all network/schema work precede
# this boundary. Locking, integrity, canonical records and atomic IO belong to I.
source_persistence_types <- function() {
  c("content_validated", "candidate_stored", "check_finished", "state_validation_failed")
}

source_persistence_eligibility <- function(observation, check_id, resolution = NULL) {
  if (!source_state_token(check_id)) source_update_abort("invalid_check_id")
  core <- names(formals(source_update_result))
  fields <- c(core, "result_version", "transport", "persistence", "context",
    "joint_acceptance_required", "planned_event_type", "content")
  source_update_object(observation, fields, fields)
  do.call(source_update_result, observation[core])
  ctx <- observation$context
  source_update_object(ctx, c("requested_identity", "effective_identity", "registry_revision",
    "contract_id", "contract_version", "contract_sha256", "state_revision", "started_at", "checked_at"),
    c("requested_identity", "effective_identity", "registry_revision", "contract_id", "contract_version",
      "contract_sha256", "state_revision", "started_at", "checked_at"))
  validate_source_request_identity(ctx$requested_identity)
  validate_source_request_identity(ctx$effective_identity)
  a <- ctx$requested_identity$descriptor; b <- ctx$effective_identity$descriptor
  if (!identical(a$source_id, b$source_id) || !identical(a$representation, b$representation) ||
      !source_string(ctx$registry_revision) || !source_string(ctx$contract_id) ||
      !source_state_integer(ctx$contract_version, 1) || !source_state_hash(ctx$contract_sha256) ||
      !source_state_time(ctx$started_at) || !source_state_time(ctx$checked_at) ||
      (!is.null(ctx$state_revision) && !source_state_integer(ctx$state_revision, 1)) ||
      !source_update_flag(observation$joint_acceptance_required) ||
      !is.null(observation$persistence) || !identical(observation$result_version, 1L)) {
    source_update_abort("invalid_persistence_observation")
  }
  # Joint observations never consume their terminal event, including failures.
  coordinated <- !is.null(resolution)
  if (coordinated) source_coordination_authorize(resolution, observation, check_id)
  if (observation$joint_acceptance_required && !coordinated) return("pending_joint_acceptance")
  if (observation$status == "blocked") return("observation_blocked")
  t <- observation$transport
  if (!is.list(t) || !identical(t$identity, ctx$effective_identity) ||
      !identical(t$requested_identity, ctx$requested_identity) ||
      !source_string(t$method) || !t$method %in% c("HEAD", "GET") || !length(t$requests)) {
    source_update_abort("invalid_terminal_transport")
  }
  last <- t$requests[[length(t$requests)]]
  if (!identical(last$identity_sha256, ctx$effective_identity$sha256) ||
      !identical(last$method, t$method) || !identical(last$url, b$absolute_request_url) ||
      !identical(last$status, t$http_status)) source_update_abort("invalid_terminal_request")
  plan <- observation$planned_event_type
  if (!source_string(plan) || !plan %in% source_persistence_types()) source_update_abort("invalid_terminal_plan")
  content_result <- t$outcome %in% c("candidate", "not_modified")
  if (content_result) {
    reused <- identical(t$outcome, "not_modified")
    expected <- if (observation$status == "incompatible_content") {
      if (reused) "state_validation_failed" else "candidate_stored"
    } else "content_validated"
    statuses <- if (reused) c("not_modified", "incompatible_content") else
      c("initialized", "content_unchanged", "content_changed", "incompatible_content")
    # C binds the exact terminal observation to an explicit joint/coverage
    # resolution. Standalone B1b retains its original acceptance gates.
    if (coordinated) {
      expected <- plan
      statuses <- c(statuses, "indeterminate", "metadata_changed")
    }
    ref <- if (reused) t$reused_content else t$content
    content <- observation$content
    source_update_object(content, c("sha256", "bytes", "relative_path", "retrieved_at"),
      c("sha256", "bytes", "relative_path", "retrieved_at"))
    validate_source_content_reference(content, b$source_id, b$representation)
    if (!identical(plan, expected) || !observation$status %in% statuses || t$method != "GET" ||
        !isTRUE(t$http_status == if (reused) 304L else 200L) ||
        !source_state_time(content$retrieved_at) ||
        !identical(source_canonical_json(content[c("sha256", "bytes", "relative_path")]), source_canonical_json(ref)) ||
        (reused && (!isTRUE(t$condition_sent) || is.null(t$condition) || isTRUE(t$recovery) || !is.null(t$retrieved_at))) ||
        (!reused && !identical(content$retrieved_at, t$retrieved_at))) source_update_abort("invalid_content_observation")
    if (!reused && !(coordinated && observation$status == "metadata_changed") && (is.null(observation$candidate) ||
        !identical(observation$candidate$identity_sha256, ctx$effective_identity$sha256) ||
        !identical(observation$candidate$sha256, content$sha256))) source_update_abort("invalid_candidate_observation")
    v <- source_update_validation_metadata(observation$validation, accepted = plan == "content_validated")
    if (!identical(v$contract_id, ctx$contract_id) || !isTRUE(v$contract_version == ctx$contract_version) ||
        !identical(v$contract_sha256, ctx$contract_sha256) ||
        (!coordinated && plan != "content_validated" && !identical(v$decision, "block"))) source_update_abort("invalid_validation_observation")
  } else {
    permitted <- if (identical(t$outcome, "metadata")) {
      t$method == "HEAD" && source_state_integer(t$http_status, 200, 299) &&
        observation$status %in% c("metadata_changed", "indeterminate")
    } else t$outcome %in% c("http_error", "transport_error", "protocol_error", "redirect_error", "argument_error") &&
      observation$status %in% c("source_unavailable", "check_failed")
    if (!isTRUE(permitted) || plan != "check_finished" || !is.null(observation$content)) {
      source_update_abort("invalid_check_observation")
    }
  }
  NULL
}

source_persistence_outcome <- function(outcome, receipt = NULL, code = NULL, error = NULL) {
  if (!source_string(outcome) || !outcome %in% c("not_attempted", "committed", "failed", "uncertain") ||
      (identical(outcome, "committed") != !is.null(receipt))) source_update_abort("invalid_persistence_outcome")
  if (!is.null(error)) source_update_result("check_failed", error = list(kind = "persistence", code = error))
  list(outcome = outcome, reason_codes = if (is.null(code)) character() else code,
    receipt = receipt, error = if (is.null(error)) NULL else list(kind = "persistence", code = error))
}

source_persistence_result <- function(observation, persistence) {
  decision <- observation
  if (!is.null(persistence$error)) {
    blocked <- persistence$outcome == "not_attempted"
    code <- persistence$error$code
    decision <- source_update_result(if (blocked) "blocked" else "check_failed",
      reason_codes = code, retryable = blocked && code %in% c("lock_busy", "stale_state_revision"),
      error = persistence$error)
  }
  list(status = decision$status, content_changed = decision$content_changed,
    severity = decision$severity, retryable = decision$retryable,
    observation = observation, persistence = persistence)
}

source_persistence_validators <- function(transport, previous = NULL) {
  headers <- list(etag = transport$observed_etag_raw, `last-modified` = transport$observed_last_modified_raw)
  current <- source_http_validators(headers[!vapply(headers, is.null, logical(1))])
  ambiguous <- current$invalid
  for (diagnostic in transport$diagnostics) {
    if (identical(diagnostic$identity_sha256, transport$identity$sha256) &&
        identical(diagnostic$code, "invalid_validator")) {
      # No attempt index is supplied by II. An omitted field with such a
      # diagnostic cannot safely be distinguished from an invalid terminal one.
      ambiguous <- union(ambiguous, diagnostic$headers)
    }
  }
  keys <- c(etag_raw = "etag", last_modified_raw = "last-modified")
  old_headers <- list(etag = previous$etag_raw, `last-modified` = previous$last_modified_raw)
  old <- source_http_validators(old_headers[!vapply(old_headers, is.null, logical(1))])
  for (key in names(keys)) {
    if (!is.null(current[[key]])) ambiguous <- setdiff(ambiguous, keys[[key]]) else
      if (!keys[[key]] %in% ambiguous && !is.null(previous)) current[key] <- old[key]
  }
  allowed <- !is.null(current$etag_raw) ||
    (!"etag" %in% ambiguous && !is.null(current$last_modified_raw))
  list(etag_raw = current$etag_raw, last_modified_raw = current$last_modified_raw,
    conditional_reuse_allowed = allowed,
    conditional_reuse_restrictions = if (allowed) list() else
      as.list(if (length(ambiguous)) "invalid_or_ambiguous_validator" else "no_valid_validator"))
}

source_persistence_event <- function(observation, check_id, resolution = NULL) {
  ctx <- observation$context
  event_id <- source_canonical_sha256(list(id_schema_version = 1L, check_id = check_id,
    request_identity_sha256 = ctx$effective_identity$sha256))
  source_state_event(observation$planned_event_type, ctx$effective_identity,
    clock = function() ctx$checked_at, id = function() event_id,
    content_sha256 = observation$content$sha256,
    decision = if (is.null(resolution)) observation$validation$decision else
      observation$validation$pair_evidence$decision %||% observation$validation$decision,
    code = if (length(observation$reason_codes)) observation$reason_codes[[1L]] else observation$status,
    check_id = check_id)
}

source_persistence_transition <- function(state, observation, event) {
  ctx <- observation$context; t <- observation$transport
  identity <- ctx$effective_identity
  if (is.null(state)) state <- new_source_state(identity)
  validate_source_state(state, identity)
  old <- state$validated_content
  if (event$type != "check_finished" || !is.null(observation$content)) {
    baseline <- if (is.null(old)) NULL else list(identity_sha256 = identity$sha256, sha256 = old$sha256)
    if (!identical(source_canonical_json(baseline), source_canonical_json(observation$baseline))) {
      source_state_block("observation_baseline_mismatch")
    }
    if (t$outcome == "not_modified") {
      fields <- c("sha256", "bytes", "relative_path", "retrieved_at")
      if (is.null(old) || !identical(source_canonical_json(old[fields]), source_canonical_json(observation$content))) {
        source_state_block("revalidation_baseline_mismatch")
      }
    }
  }
  if (event$type == "content_validated") {
    validation <- source_update_validation_metadata(observation$validation, accepted = TRUE)
    if (t$outcome == "candidate") {
      classified <- source_update_classify_representation("accepted_200", identity$sha256,
        observation$content$sha256, observation$baseline)
      if (!identical(classified$status, observation$status)) source_state_block("observation_classification_mismatch")
      state <- source_state_candidate(state, observation$content, validation, function() observation$content$retrieved_at)
      state <- source_state_promote(state, validation, function() ctx$checked_at)
      if (!is.null(old) && !identical(old$sha256, observation$content$sha256)) {
        state$last_confirmed_content_change <- list(observed_at = observation$content$retrieved_at,
          previous_sha256 = old$sha256, observed_sha256 = observation$content$sha256,
          candidate_accepted = TRUE, event_id = event$event_id)
      }
    } else {
      state$validated_content$validation <- validation
      state$validated_content$validated_at <- ctx$checked_at
    }
    validators <- source_persistence_validators(t, if (t$outcome == "not_modified") old else NULL)
    state$validated_content[names(validators)] <- validators
    if (!is.null(state$last_error) && is.null(state$last_error$resolved_at)) state$last_error$resolved_at <- ctx$checked_at
  } else if (event$type == "candidate_stored") {
    state <- source_state_candidate(state, observation$content,
      source_update_validation_metadata(observation$validation), function() observation$content$retrieved_at)
  }
  reasons <- observation$reason_codes
  # The existing reason-code slot carries comparability of last_http_observation.
  # A check without a response retains that observation and its ambiguity.
  if (is.null(t$http_status) && "last_http_invalid_validator" %in% state$last_check$reason_codes) {
    reasons <- unique(c(reasons, "last_http_invalid_validator"))
  }
  state$last_check <- list(check_id = event$check_id, started_at = ctx$started_at,
    finished_at = ctx$checked_at, status = observation$status, reason_codes = as.list(reasons))
  state$registry_revision_seen <- ctx$registry_revision
  if (!is.null(t$http_status)) {
    last <- t$requests[[length(t$requests)]]
    state$last_http_observation <- list(observed_at = ctx$checked_at, method = t$method,
      request_url = last$url, http_status = t$http_status, etag_raw = t$observed_etag_raw,
      last_modified_raw = t$observed_last_modified_raw, event_id = event$event_id)
  }
  if (observation$status %in% c("incompatible_content", "source_unavailable", "check_failed")) {
    state$last_error <- list(observed_at = ctx$checked_at,
      code = if (is.null(observation$error)) event$code else observation$error$code,
      kind = if (is.null(observation$error)) "validation" else observation$error$kind, resolved_at = NULL)
  }
  validate_source_state(state, identity)
  state
}

source_persistence_require_content <- function(config, state) {
  for (field in c("validated_content", "latest_candidate")) if (!is.null(state[[field]])) {
    source_require_content(config, state$source_id, state$representation, state[[field]])
  }
  invisible(TRUE)
}

source_persistence_matches <- function(record, prepared) {
  expected <- prepared$state_after
  expected$state_revision <- prepared$generation + 1L
  isTRUE(record$state_revision == prepared$generation + 1L) &&
    identical(record$previous_record_sha256, prepared$head_sha256) &&
    identical(source_canonical_json(record$event), source_canonical_json(prepared$event)) &&
    identical(source_canonical_json(record$state_after), source_canonical_json(expected))
}

# Only call with a record from the fully validated revision chain.
source_persistence_receipt <- function(record) {
  c(record$event[c("source_id", "representation", "request_identity_sha256")],
    list(state_revision = record$state_revision), record$event[c("event_id", "check_id", "type")],
    list(record_sha256 = record$record_sha256))
}

source_persistence_prepare <- function(config, observation, check_id, lock, resolution = NULL) {
  gate <- source_persistence_eligibility(observation, check_id, resolution)
  if (!is.null(gate)) source_state_block(gate)
  identity <- observation$context$effective_identity
  assert_source_lock(config, identity$descriptor$source_id, lock)
  records <- read_source_revisions(config, identity)
  generation <- observation$context$state_revision %||% 0L
  event <- source_persistence_event(observation, check_id, resolution)
  found <- which(vapply(records, function(r) identical(r$event$event_id, event$event_id) ||
    (identical(r$event$check_id, check_id) && r$event$type %in% source_persistence_types()), logical(1)))
  if (length(found) && (length(found) != 1L || found != generation + 1L)) source_state_block("check_id_conflict")
  if (!length(found) && length(records) != generation) source_state_block("stale_state_revision")
  previous <- if (generation) records[[generation]] else NULL
  prepared <- list(identity = identity, generation = generation, head_sha256 = previous$record_sha256,
    event = event, state_after = source_persistence_transition(previous$state_after, observation, event), receipt = NULL)
  if (length(found)) {
    record <- records[[found]]
    if (!source_persistence_matches(record, prepared)) source_state_block("check_id_conflict")
    # Historical confirmation does not assert that this is still the current head.
    prepared$receipt <- source_persistence_receipt(record)
  } else source_persistence_require_content(config, prepared$state_after)
  prepared
}

source_persistence_reconcile <- function(config, prepared, lock) {
  tryCatch({
    assert_source_lock(config, prepared$identity$descriptor$source_id, lock)
    records <- read_source_revisions(config, prepared$identity)
    index <- prepared$generation + 1L
    if (length(records) >= index) {
      if (!source_persistence_matches(records[[index]], prepared)) {
        return(source_persistence_outcome("uncertain", error = "terminal_record_conflict"))
      }
      return(source_persistence_outcome("committed", source_persistence_receipt(records[[index]])))
    }
    head <- if (length(records)) records[[length(records)]]$record_sha256 else NULL
    if (length(records) == prepared$generation && identical(head, prepared$head_sha256)) {
      return(source_persistence_outcome("failed", error = "terminal_record_absent"))
    }
    source_persistence_outcome("uncertain", error = "terminal_record_unconfirmed")
  }, source_state_block = function(e) source_persistence_outcome("uncertain", error = e$code))
}

source_persistence_commit <- function(config, prepared, lock, hooks = list()) {
  assert_source_lock(config, prepared$identity$descriptor$source_id, lock)
  records <- read_source_revisions(config, prepared$identity)
  head <- if (length(records)) records[[length(records)]]$record_sha256 else NULL
  if (length(records) != prepared$generation || !identical(head, prepared$head_sha256)) source_state_block("stale_state_revision")
  source_persistence_require_content(config, prepared$state_after)
  failure <- tryCatch({
    commit_source_event(config, prepared$identity, prepared$event, prepared$state_after, lock = lock, hooks = hooks)
    NULL
  }, source_state_block = function(e) e)
  # Unexpected programming/untagged IO errors propagate; explicit retry with the
  # same check ID can still reconcile a revision already left by that invocation.
  persistence <- source_persistence_reconcile(config, prepared, lock)
  if (persistence$outcome == "committed") {
    if (!is.null(failure)) persistence$reason_codes <- "commit_reconciled"
    # Once the record is proved, subsequent integrity diagnostics cannot undo it.
    tryCatch(source_persistence_require_content(config, prepared$state_after), source_state_block = function(e) {
      persistence$error <<- list(kind = "persistence", code = e$code)
    })
  } else if (!is.null(failure)) persistence$reason_codes <- failure$code
  persistence
}

source_persistence_representation <- function(config, observation, check_id, lock = NULL,
                                              hooks = list(), clock = source_state_now, id = source_state_id) {
  gate <- source_persistence_eligibility(observation, check_id)
  if (!is.null(gate)) return(source_persistence_result(observation,
    source_persistence_outcome("not_attempted", code = gate)))
  persistence <- NULL; primary_error <- NULL
  tryCatch({
    tryCatch(with_source_lock(config, observation$context$effective_identity$descriptor$source_id, function(held) {
      # Observe escaping body errors before on.exit cleanup can replace them.
      withCallingHandlers({
        prepared <- source_persistence_prepare(config, observation, check_id, held)
        persistence <<- if (!is.null(prepared$receipt)) source_persistence_outcome("committed", prepared$receipt,
          code = "already_committed") else source_persistence_commit(config, prepared, held, hooks)
      }, error = function(e) primary_error <<- e)
    }, lock = lock, clock = clock, id = id), error = function(e) {
      # Rethrow the original condition; never classify an unexpected error.
      stop(if (is.null(primary_error)) e else primary_error)
    })
  }, source_state_block = function(e) {
    if (is.null(persistence)) persistence <<- source_persistence_outcome("not_attempted", error = e$code) else {
      # Includes failure of the owned lock's on.exit release after a proved write.
      persistence$error <<- list(kind = "persistence", code = e$code)
    }
  })
  source_persistence_result(observation, persistence)
}

# Unit C. A cycle is an in-memory replay input, not a durable journal. It keeps
# B1a observations separate from joint decisions and from confirmed receipts.
source_coordination_source <- function(registry, source_id) {
  validate_source_registry(registry)
  found <- Filter(function(s) identical(s$source_id, source_id) && isTRUE(s$enabled), registry$sources)
  if (length(found) != 1L) source_update_abort("unknown_coordination_source")
  found[[1L]]
}

source_coordination_cycle <- function(observations, check_id, registry, source_id, kind) {
  source <- source_coordination_source(registry, source_id)
  formats <- if (kind == "pair") c("json", "csv") else "json"
  source_update_object(observations, formats)
  observations <- stats::setNames(lapply(formats, function(fmt) observations[[fmt]]), formats)
  cycle <- list(cycle_version = 1L, kind = kind, source_id = source_id, source_role = source$role,
    check_id = check_id, registry_revision = registry$registry_revision,
    registry_sha256 = source_canonical_sha256(registry), observations = observations,
    pair = NULL, coverage = NULL, error = NULL)
  source_coordination_validate(cycle)
  cycle
}

source_coordination_validate <- function(cycle) {
  fields <- c("cycle_version", "kind", "source_id", "source_role", "check_id", "registry_revision",
    "registry_sha256", "observations", "pair", "coverage", "error")
  source_update_object(cycle, fields, fields)
  if (!identical(cycle$cycle_version, 1L) || !source_state_token(cycle$check_id) ||
      !source_string(cycle$registry_revision) || !source_state_hash(cycle$registry_sha256) ||
      !source_string(cycle$kind) || !cycle$kind %in% c("pair", "catalog")) source_update_abort("invalid_cycle")
  source_state_namespace(cycle$source_id)
  if (!(if (cycle$kind == "pair") cycle$source_role %in% c("complete_base", "thematic_subset") else
      identical(cycle$source_role, "catalog"))) source_update_abort("invalid_cycle_role")
  formats <- if (cycle$kind == "pair") c("json", "csv") else "json"
  source_update_object(cycle$observations, formats, formats)
  contexts <- list(); methods <- character()
  for (fmt in formats) {
    obs <- cycle$observations[[fmt]]
    if (is.null(obs)) next
    source_persistence_eligibility(obs, cycle$check_id)
    ctx <- obs$context; d <- ctx$effective_identity$descriptor
    if (!identical(d$source_id, cycle$source_id) || !identical(d$representation, fmt) ||
        !identical(ctx$registry_revision, cycle$registry_revision) ||
        (cycle$kind == "pair" && !isTRUE(obs$joint_acceptance_required))) source_update_abort("incompatible_cycle_observation")
    contexts[[fmt]] <- ctx[c("contract_id", "contract_version", "contract_sha256")]
    methods <- c(methods, obs$transport$method)
  }
  if (length(unique(methods)) > 1L || (length(contexts) == 2L &&
      !identical(contexts[[1L]], contexts[[2L]]))) source_update_abort("incompatible_cycle_contract")
  if (!is.null(cycle$error)) {
    source_update_object(cycle$error, c("status", "code"), c("status", "code"))
    source_update_result(cycle$error$status, reason_codes = cycle$error$code)
  }
  if (!is.null(cycle$pair)) {
    p <- cycle$pair
    self <- c("representation", "requested_identity_sha256", "effective_identity_sha256", "content_sha256")
    keys <- c("check_id", "classification", "decision", "contract_id", "contract_version",
      "contract_sha256", "registry_revision", "comparison", self, "partner")
    source_update_object(p, keys, keys)
    adapted <- source_update_validation_metadata(list(decision = "allow", classification = "valid", pair_evidence = p))$pair_evidence
    if (cycle$kind != "pair" || length(contexts) != 2L ||
        !all(vapply(cycle$observations, source_coordination_content_valid, logical(1))) ||
        !identical(p$check_id, cycle$check_id) || !identical(p$registry_revision, cycle$registry_revision) ||
        !identical(source_canonical_json(p[self]), source_canonical_json(source_coordination_member(cycle$observations$json))) ||
        !identical(source_canonical_json(p$partner), source_canonical_json(source_coordination_member(cycle$observations$csv))) ||
        !identical(source_canonical_json(p), source_canonical_json(adapted)) ||
        !identical(source_canonical_json(p[names(contexts[[1L]])]), source_canonical_json(contexts[[1L]])) ||
        !p$classification %in% c("consistent_under_projection", "inconsistent_under_projection", "insufficient_evidence") ||
        (p$classification == "inconsistent_under_projection" && p$decision != "block") ||
        (p$classification == "insufficient_evidence" && p$decision != "warn") ||
        (p$classification == "consistent_under_projection" && (p$decision == "block" ||
          !isTRUE(p$comparison$row_multiset_matches) || length(p$comparison$unsupported_fields)))) {
      source_update_abort("invalid_joint_evidence")
    }
  }
  if (!is.null(cycle$coverage)) {
    source_update_object(cycle$coverage, c("classification", "decision", "mapping", "issues"),
      c("classification", "decision", "mapping", "issues"))
    if (cycle$kind != "catalog" || !cycle$coverage$decision %in% c("allow", "review", "block") ||
        !is.data.frame(cycle$coverage$mapping) || !is.data.frame(cycle$coverage$issues)) source_update_abort("invalid_coverage")
  }
  invisible(TRUE)
}

source_coordination_content_valid <- function(obs) {
  !is.null(obs$content) && obs$status != "blocked" && !is.null(obs$validation) &&
    obs$validation$decision %in% c("allow", "warn") && obs$transport$outcome %in% c("candidate", "not_modified")
}

source_coordination_member <- function(obs) {
  list(representation = obs$context$effective_identity$descriptor$representation,
    requested_identity_sha256 = obs$context$requested_identity$sha256,
    effective_identity_sha256 = obs$context$effective_identity$sha256, content_sha256 = obs$content$sha256)
}

source_coordination_read <- function(config, observation, reader = read_source_payload) {
  ctx <- observation$context; d <- ctx$effective_identity$descriptor
  source_require_content(config, d$source_id, d$representation, observation$content)
  path <- source_safe_path(source_operational_root(config), observation$content$relative_path)
  payload <- reader(path, d$representation)
  source_require_content(config, d$source_id, d$representation, observation$content)
  payload
}

source_coordination_contract <- function(cycle, registry, contract_loader) {
  source <- source_coordination_source(registry, cycle$source_id)
  contract <- contract_loader(source$representations$json$contract)
  validate_schema_contract(contract)
  for (obs in cycle$observations) if (!is.null(obs) &&
      (!identical(obs$context$contract_id, contract$contract_id) ||
       !isTRUE(obs$context$contract_version == contract$version) ||
       !identical(obs$context$contract_sha256, source_canonical_sha256(contract)))) {
    source_update_abort("cycle_contract_changed")
  }
  contract
}

source_coordination_resolve <- function(config, observations, check_id, registry = load_source_registry(),
                                       source_id, contract_loader = load_schema_contract,
                                       reader = read_source_payload, pair_validator = validate_source_pair) {
  cycle <- source_coordination_cycle(observations, check_id, registry, source_id, "pair")
  contract <- source_coordination_contract(cycle, registry, contract_loader)
  if (all(vapply(cycle$observations, source_coordination_content_valid, logical(1)))) {
    tryCatch({
      json <- source_coordination_read(config, cycle$observations$json, reader)
      csv <- source_coordination_read(config, cycle$observations$csv, reader)
      pair <- pair_validator(json, csv, contract, source_id)
      comparison <- pair[intersect(names(pair), names(source_update_validation_shape()$pair_evidence$comparison))]
      decision <- pair$decision
      if (pair$classification == "consistent_under_projection" && cycle$observations$json$validation$decision == "warn") decision <- "warn"
      evidence <- list(check_id = check_id, classification = pair$classification, decision = decision,
        contract_id = contract$contract_id, contract_version = contract$version,
        contract_sha256 = source_canonical_sha256(contract), registry_revision = registry$registry_revision,
        comparison = comparison)
      evidence <- c(evidence, source_coordination_member(cycle$observations$json),
        list(partner = source_coordination_member(cycle$observations$csv)))
      cycle$pair <- source_update_validation_metadata(list(decision = "allow", classification = "valid",
        pair_evidence = evidence))$pair_evidence
    }, source_state_block = function(e) cycle$error <<- list(status = "blocked", code = e$code))
  }
  source_coordination_validate(cycle)
  cycle
}

# Schema and coverage are separate observations. A global coverage block never
# exposes a supposedly unaffected subset of executable mappings.
source_coordination_catalog <- function(config, observation, check_id, registry = load_source_registry(),
                                       contract_loader = load_schema_contract, reader = read_source_payload) {
  cycle <- source_coordination_cycle(list(json = observation), check_id, registry,
    observation$context$effective_identity$descriptor$source_id, "catalog")
  source_coordination_contract(cycle, registry, contract_loader)
  if (source_coordination_content_valid(observation)) tryCatch({
    cycle$coverage <- reconcile_source_catalog(registry, source_coordination_read(config, observation, reader))
    if (cycle$coverage$decision == "block") cycle$coverage$mapping <- cycle$coverage$mapping[FALSE, , drop = FALSE]
  }, source_state_block = function(e) cycle$error <<- list(status = "blocked", code = e$code))
  source_coordination_validate(cycle)
  cycle
}

source_coordination_observe <- function(config, source_id, catalog, check_id, registry = load_source_registry(),
                                       allow_download = FALSE, force_content = FALSE,
                                       execute = httr2::req_perform, clock = source_state_now, sleep = Sys.sleep,
                                       contract_loader = load_schema_contract) {
  cycle <- source_coordination_cycle(list(), check_id, registry, source_id, "pair")
  source_coordination_validate(catalog)
  if (catalog$kind != "catalog" || !identical(catalog$registry_sha256, cycle$registry_sha256)) source_update_abort("incompatible_catalog_cycle")
  if (!source_update_flag(allow_download) || !source_update_flag(force_content) ||
      (!allow_download && force_content)) source_update_abort("invalid_download_contract")
  if (!is.null(catalog$error) || any(vapply(catalog$observations, function(o) o$status == "blocked", logical(1))) ||
      identical(catalog$coverage$decision, "block")) {
    cycle$error <- list(status = "blocked", code = "catalog_blocked"); return(cycle)
  }
  if (is.null(catalog$coverage)) {
    cycle$error <- list(status = "indeterminate", code = "catalog_resolution_unavailable"); return(cycle)
  }
  mapping <- catalog$coverage$mapping
  mapping <- mapping[mapping$source_id == source_id & mapping$enabled, , drop = FALSE]
  if (nrow(mapping) != 2L || !setequal(mapping$representation, c("json", "csv"))) source_update_abort("invalid_catalog_mapping")
  identities <- lapply(c("json", "csv"), function(fmt) source_request_identity(source_id, fmt,
    mapping$url[mapping$representation == fmt], registry))
  observations <- stats::setNames(lapply(identities, function(identity) source_observation_representation(
    config, identity, registry, allow_download = allow_download, force_content = force_content,
    joint_acceptance_required = TRUE, execute = execute, clock = clock, sleep = sleep,
    contract_loader = contract_loader)), c("json", "csv"))
  source_coordination_resolve(config, observations, check_id, registry, source_id, contract_loader)
}

source_coordination_accepted <- function(cycle) {
  if (!is.null(cycle$error)) return(FALSE)
  if (cycle$kind == "catalog") return(!is.null(cycle$coverage) && cycle$coverage$decision != "block" &&
    source_coordination_content_valid(cycle$observations$json))
  !is.null(cycle$pair) && cycle$pair$classification == "consistent_under_projection" &&
    cycle$pair$decision %in% c("allow", "warn")
}

source_coordination_evidence <- function(cycle, fmt) {
  if (is.null(cycle$pair)) return(NULL)
  # No own/partner event_id or state_revision: these are logical facts only.
  evidence <- cycle$pair
  if (fmt == "csv") {
    self <- names(evidence$partner)
    evidence[self] <- cycle$pair$partner
    evidence$partner <- cycle$pair[self]
  }
  evidence
}

source_coordination_terminal <- function(cycle, fmt) {
  obs <- cycle$observations[[fmt]]
  if (is.null(obs) || obs$status == "blocked") return(obs)
  v <- obs$validation; plan <- obs$planned_event_type; status <- obs$status
  accepted <- source_coordination_accepted(cycle)
  if (!is.null(obs$content)) {
    reused <- obs$transport$outcome == "not_modified"
    if (cycle$kind == "pair" && !is.null(cycle$pair)) v$pair_evidence <- source_coordination_evidence(cycle, fmt)
    coverage_block <- cycle$kind == "catalog" && identical(cycle$coverage$decision, "block")
    if (coverage_block) { v$decision <- "block"; v$classification <- "breaking"; v$kind <- "catalog_coverage" }
    if (v$decision == "block") {
      status <- "incompatible_content"; plan <- if (reused) "state_validation_failed" else "candidate_stored"
    } else if (accepted) {
      status <- source_update_classify_representation(if (reused) "accepted_304" else "accepted_200",
        obs$context$effective_identity$sha256, if (reused) NULL else obs$content$sha256, obs$baseline)$status
      plan <- "content_validated"
    } else {
      status <- if (identical(cycle$pair$decision, "block")) "incompatible_content" else
        if (isTRUE(obs$metadata_changed)) "metadata_changed" else "indeterminate"
      plan <- if (reused) "check_finished" else "candidate_stored"
    }
  }
  reasons <- obs$reason_codes
  if (cycle$kind == "pair") reasons <- unique(c(if (accepted) "joint_accepted" else "joint_acceptance_pending",
    if (!is.null(cycle$pair)) paste0("pair_", cycle$pair$classification), setdiff(reasons, "joint_acceptance_pending")))
  if (!is.null(cycle$coverage)) reasons <- unique(c(paste0("coverage_", cycle$coverage$classification),
    cycle$coverage$issues$code, reasons))
  candidate <- if (is.null(obs$content) || obs$transport$outcome == "not_modified" || status == "metadata_changed") NULL else
    list(identity_sha256 = obs$context$effective_identity$sha256, sha256 = obs$content$sha256)
  core <- source_update_result(status, metadata_changed = obs$metadata_changed, redirected = obs$redirected,
    reason_codes = reasons, retryable = obs$retryable, baseline = obs$baseline,
    candidate = candidate, validation = v, error = obs$error)
  obs[names(core)[!names(core) %in% c("transport", "persistence")]] <- core[!names(core) %in% c("transport", "persistence")]
  obs["planned_event_type"] <- list(plan)
  obs
}

source_coordination_authorize <- function(cycle, observation, check_id) {
  source_coordination_validate(cycle)
  fmt <- observation$context$effective_identity$descriptor$representation
  if (!identical(cycle$check_id, check_id) || !is.null(cycle$error) ||
      !identical(observation, source_coordination_terminal(cycle, fmt))) source_update_abort("invalid_coordination_resolution")
  invisible(TRUE)
}

# Check reciprocal logical evidence AND locate both actual acceptance records.
# A single accepted record, or matching bytes from different checks, is not a
# jointly persisted baseline. Later check_finished events do not erase proof.
source_coordination_baseline <- function(cycle, chains) {
  if (cycle$kind != "pair" || any(vapply(cycle$observations, is.null, logical(1)))) return(FALSE)
  contents <- lapply(names(chains), function(fmt) {
    g <- cycle$observations[[fmt]]$context$state_revision %||% 0L
    if (!g || length(chains[[fmt]]) < g) NULL else chains[[fmt]][[g]]$state_after$validated_content
  })
  names(contents) <- names(chains)
  if (length(contents) != 2L || any(vapply(contents, is.null, logical(1)))) return(FALSE)
  evidence <- lapply(contents, function(x) x$validation$pair_evidence)
  if (any(vapply(evidence, is.null, logical(1)))) return(FALSE)
  common <- c("check_id", "classification", "decision", "contract_id", "contract_version", "contract_sha256", "registry_revision", "comparison")
  for (fmt in c("json", "csv")) {
    p <- evidence[[fmt]]; partner <- if (fmt == "json") "csv" else "json"; q <- evidence[[partner]]
    self <- c("representation", "requested_identity_sha256", "effective_identity_sha256", "content_sha256")
    if (!all(c(common, self, "partner") %in% names(p)) || p$classification != "consistent_under_projection" ||
        !p$decision %in% c("allow", "warn") || !identical(p$representation, fmt) ||
        !identical(p$effective_identity_sha256, cycle$observations[[fmt]]$context$effective_identity$sha256) ||
        !identical(p$content_sha256, contents[[fmt]]$sha256) ||
        !identical(source_canonical_json(p[common]), source_canonical_json(q[common])) ||
        !identical(source_canonical_json(p$partner), source_canonical_json(q[self]))) return(FALSE)
    proof <- Filter(function(r) identical(r$event$check_id, p$check_id) && r$event$type == "content_validated" &&
      identical(r$event$content_sha256, p$content_sha256) &&
      identical(source_canonical_json(r$state_after$validated_content$validation$pair_evidence), source_canonical_json(p)), chains[[fmt]])
    if (length(proof) != 1L) return(FALSE)
  }
  TRUE
}

source_coordination_assess <- function(cycle, baseline = FALSE) {
  observations <- Filter(Negate(is.null), cycle$observations)
  statuses <- vapply(observations, function(o) o$status, character(1))
  status <- "indeterminate"; reason <- "joint_acceptance_pending"; retryable <- FALSE
  if (!is.null(cycle$error)) { status <- cycle$error$status; reason <- cycle$error$code } else {
    failures <- c("blocked", "check_failed", "incompatible_content", "source_unavailable")
    hit <- failures[failures %in% statuses]
    if (length(hit)) {
      status <- hit[[1L]]
      selected <- observations[statuses == status]
      reason <- unique(unlist(lapply(selected, `[[`, "reason_codes"), use.names = FALSE))
      retryable <- any(vapply(selected, function(o) isTRUE(o$retryable), logical(1)))
    } else if (identical(cycle$pair$decision, "block") || identical(cycle$coverage$decision, "block")) {
      status <- "incompatible_content"; reason <- if (cycle$kind == "pair") "pair_inconsistent" else "coverage_blocked"
    } else if (source_coordination_accepted(cycle)) {
      terminal <- lapply(names(observations), function(fmt) source_coordination_terminal(cycle, fmt))
      states <- vapply(terminal, `[[`, character(1), "status")
      status <- if (cycle$kind == "catalog") states[[1L]] else if (!baseline) "initialized" else
        if ("content_changed" %in% states) "content_changed" else
        if (all(states == "content_unchanged")) "content_unchanged" else "not_modified"
      reason <- if (cycle$kind == "pair") "joint_accepted" else "catalog_accepted"
    } else if (length(observations) == length(cycle$observations) &&
        all(vapply(observations, function(o) identical(o$transport$method, "HEAD"), logical(1))) &&
        any(vapply(observations, function(o) isTRUE(o$metadata_changed), logical(1)))) {
      status <- "metadata_changed"; reason <- "head_metadata_changed"
    }
  }
  warning <- identical(cycle$pair$decision, "warn") || identical(cycle$coverage$decision, "review")
  list(status = status, content_changed = switch(status, content_changed = TRUE, content_unchanged = FALSE, NA),
    severity = if (status %in% c("blocked", "check_failed", "incompatible_content", "source_unavailable")) "error" else
      if (warning) "warning" else "normal", reason_codes = reason, retryable = retryable)
}

source_coordination_prepare <- function(config, cycle, lock, confirmed = function(fmt, receipt) NULL) {
  assert_source_lock(config, cycle$source_id, lock)
  prepared <- list(); chains <- list(); failures <- list()
  # Keep inspecting the partner after a known pre-write block, so a historical
  # receipt is not lost merely because the other generation is stale/corrupt.
  for (fmt in names(cycle$observations)) if (!is.null(cycle$observations[[fmt]])) tryCatch({
    obs <- source_coordination_terminal(cycle, fmt)
    chains[[fmt]] <- read_source_revisions(config, obs$context$effective_identity)
    p <- source_persistence_prepare(config, obs, cycle$check_id, lock, resolution = cycle)
    prepared[[fmt]] <- p
    if (!is.null(p$receipt)) confirmed(fmt, p$receipt)
  }, source_state_block = function(e) failures[[length(failures) + 1L]] <<- e)
  if (length(failures)) stop(failures[[1L]])
  pending <- vapply(prepared, function(p) is.null(p$receipt), logical(1))
  for (fmt in names(prepared)) {
    p <- prepared[[fmt]]
    if (any(pending)) {
      # Confirm both heads after preparation, before either new commit. The
      # borrowed lock may also be used by the caller's composition primitives.
      current <- read_source_revisions(config, p$identity)
      head <- if (length(current)) current[[length(current)]]$record_sha256 else NULL
      generation <- if (pending[[fmt]]) p$generation else p$receipt$state_revision
      checksum <- if (pending[[fmt]]) p$head_sha256 else p$receipt$record_sha256
      if (length(current) != generation || !identical(head, checksum)) source_state_block("stale_state_revision")
      source_persistence_require_content(config, p$state_after)
    }
  }
  list(prepared = prepared, baseline = source_coordination_baseline(cycle, chains))
}

source_coordination_result <- function(cycle, assessment, outcomes, failure = NULL) {
  states <- vapply(outcomes, `[[`, character(1), "outcome")
  committed <- states == "committed"
  outcome <- if (all(committed)) "committed" else if (any(committed)) "partial" else
    if ("uncertain" %in% states) "uncertain" else if ("failed" %in% states) "failed" else "not_attempted"
  result <- assessment
  failed <- !is.null(failure) || any(states %in% c("failed", "uncertain")) ||
    any(vapply(outcomes, function(p) !is.null(p$error), logical(1)))
  if (failed) {
    result$status <- if (!any(committed) && all(states == "not_attempted")) "blocked" else "check_failed"
    result$content_changed <- NA; result$severity <- "error"
    result$reason_codes <- unique(c(failure$code, unlist(lapply(outcomes, function(p) c(p$reason_codes, p$error$code)), use.names = FALSE)))
    result$retryable <- result$status == "blocked" && any(result$reason_codes %in% c("lock_busy", "stale_state_revision"))
  }
  representations <- stats::setNames(lapply(names(outcomes), function(fmt) list(observation = cycle$observations[[fmt]],
    terminal = source_coordination_terminal(cycle, fmt), persistence = outcomes[[fmt]])), names(outcomes))
  c(list(result_version = 1L, source_id = cycle$source_id, source_role = cycle$source_role, check_id = cycle$check_id,
    registry_revision = cycle$registry_revision, assessment = assessment, representations = representations,
    pair = cycle$pair, coverage = cycle$coverage,
    joint_acceptance = list(accepted = source_coordination_accepted(cycle),
      baseline_confirmed = cycle$kind == "pair" && source_coordination_accepted(cycle) && all(committed)),
    persistence = list(outcome = outcome, representations = outcomes, error = failure)), result)
}

source_coordination_persist <- function(config, cycle, lock = NULL, hooks = list(),
                                       clock = source_state_now, id = source_state_id) {
  source_coordination_validate(cycle)
  source_update_object(hooks, c("json", "csv"))
  outcomes <- lapply(cycle$observations, function(o) source_persistence_outcome("not_attempted",
    code = if (is.null(o)) "representation_absent" else NULL))
  assessment <- source_coordination_assess(cycle)
  if (!is.null(cycle$error) || assessment$status == "blocked" || all(vapply(cycle$observations, is.null, logical(1)))) {
    return(source_coordination_result(cycle, assessment, outcomes))
  }
  primary <- NULL; failure <- NULL
  tryCatch({
    tryCatch(with_source_lock(config, cycle$source_id, function(held) {
      withCallingHandlers({
        prepared <- source_coordination_prepare(config, cycle, held, function(fmt, receipt) {
          outcomes[[fmt]] <<- source_persistence_outcome("committed", receipt, code = "already_committed")
        })
        assessment <<- source_coordination_assess(cycle, prepared$baseline)
        for (fmt in names(prepared$prepared)) {
          p <- prepared$prepared[[fmt]]
          if (!is.null(p$receipt)) next
          outcomes[[fmt]] <<- source_persistence_commit(config, p, held, hooks[[fmt]] %||% list())
          if (outcomes[[fmt]]$outcome != "committed" || !is.null(outcomes[[fmt]]$error)) break
        }
      }, error = function(e) primary <<- e)
    }, lock = lock, clock = clock, id = id), error = function(e) stop(if (is.null(primary)) e else primary))
  }, source_state_block = function(e) failure <<- list(kind = "persistence", code = e$code))
  source_coordination_result(cycle, assessment, outcomes, failure)
}
