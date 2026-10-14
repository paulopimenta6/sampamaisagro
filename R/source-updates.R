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
