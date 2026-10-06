# Checkpoint 1B: immutable step I identities; internal step II transport below.
# Canonical JSON v1: UTF-8 keys sorted by radix; arrays retain order; scalars
# are unboxed; NULL is null; finite numbers use 17 significant decimal digits.
# Integer/double share a number family and signed zero is zero. No NA, classed
# values, duplicate keys or locale-dependent transliteration are accepted.
source_canonical_json <- function(x) {
  string <- function(value) {
    value <- enc2utf8(value)
    if (anyNA(iconv(value, from = "UTF-8", to = "UTF-8"))) {
      stop("Invalid canonical UTF-8 string.", call. = FALSE)
    }
    as.character(jsonlite::toJSON(value, auto_unbox = TRUE))
  }
  encode <- function(value) {
    if (is.null(value)) return("null")
    attrs <- setdiff(names(attributes(value)), "names")
    if (length(attrs)) stop("Unsupported canonical attributes.", call. = FALSE)
    if (is.list(value)) {
      keys <- names(value)
      if (is.null(keys)) return(paste0("[", paste(vapply(value, encode, character(1)), collapse = ","), "]"))
      keys <- enc2utf8(keys)
      if (anyNA(keys) || any(!nzchar(keys)) || anyDuplicated(keys)) {
        stop("Invalid canonical object keys.", call. = FALSE)
      }
      order <- order(keys, method = "radix")
      pairs <- vapply(order, function(i) paste0(string(keys[i]), ":", encode(value[[i]])), character(1))
      return(paste0("{", paste(pairs, collapse = ","), "}"))
    }
    if (!is.null(names(value)) || !is.atomic(value) || is.raw(value) || is.complex(value) || anyNA(value)) {
      stop("Unsupported canonical value.", call. = FALSE)
    }
    if (length(value) != 1L) return(encode(as.list(value)))
    if (is.character(value)) return(string(value))
    if (is.logical(value)) return(if (value) "true" else "false")
    if (is.numeric(value) && is.finite(value)) {
      if (value == 0) return("0")
      return(trimws(formatC(value, digits = 17L, format = "g", decimal.mark = ".")))
    }
    stop("Unsupported canonical scalar.", call. = FALSE)
  }
  enc2utf8(encode(x))
}

source_canonical_sha256 <- function(x) {
  digest::digest(charToRaw(source_canonical_json(x)), algo = "sha256", serialize = FALSE)
}

source_request_descriptor <- function(source_id, representation, url,
                                      registry = load_source_registry(), request_headers = list()) {
  validate_source_registry(registry)
  source <- Filter(function(s) identical(s$source_id, source_id), registry$sources)
  if (length(source) != 1L || !isTRUE(source[[1]]$enabled)) stop("Unknown or disabled source identity.", call. = FALSE)
  source <- source[[1]]
  if (!source_string(representation) || !representation %in% names(source$representations)) {
    stop("Invalid source representation.", call. = FALSE)
  }
  if (is.null(source_url_parts(url, registry$url_policy))) stop("Invalid request URL policy.", call. = FALSE)
  if (source$role %in% c("complete_base", "thematic_subset") &&
      !identical(source_catalog_slug(url, representation, registry$url_policy), source$catalog_slug)) {
    stop("Request URL slug/representation mismatch.", call. = FALSE)
  }
  if (!is.list(request_headers) || (length(request_headers) && is.null(names(request_headers)))) {
    stop("Invalid request headers.", call. = FALSE)
  }
  keys <- tolower(gsub("_", "-", names(request_headers), fixed = TRUE))
  if (anyNA(keys) || anyDuplicated(keys) || any(!keys %in% c("accept", "accept-encoding",
      "user-agent", "if-none-match", "if-modified-since"))) stop("Unsupported request header.", call. = FALSE)
  names(request_headers) <- keys
  accept <- if ("accept" %in% keys) request_headers$accept else switch(representation, json = "application/json", csv = "text/csv", html = "text/html")
  encoding <- if ("accept-encoding" %in% keys) request_headers[["accept-encoding"]] else "identity"
  for (value in list(accept, encoding)) {
    if (!source_string(value) || grepl("[[:cntrl:]]", value)) stop("Invalid negotiation header.", call. = FALSE)
  }
  # User-Agent contains the local application version; no representation
  # negotiation by that header is demonstrated. Only these two headers bind v1.
  list(identity_version = 1L, source_id = source_id, representation = representation,
    absolute_request_url = url, representation_method = "GET",
    request_headers = list(accept = accept, accept_encoding = encoding))
}

source_request_identity <- function(source_id, representation, url,
                                    registry = load_source_registry(), request_headers = list()) {
  descriptor <- source_request_descriptor(source_id, representation, url, registry, request_headers)
  list(descriptor = descriptor, canonical = source_canonical_json(descriptor),
    sha256 = source_canonical_sha256(descriptor))
}

validate_source_request_identity <- function(identity) {
  source_keys(identity, c("descriptor", "canonical", "sha256"), "request identity")
  if (!setequal(names(identity), c("descriptor", "canonical", "sha256"))) stop("Incomplete request identity.", call. = FALSE)
  d <- identity$descriptor
  fields <- c("identity_version", "source_id", "representation", "absolute_request_url", "representation_method", "request_headers")
  source_keys(d, fields, "request descriptor")
  if (!setequal(names(d), fields) || !isTRUE(d$identity_version == 1) ||
      !source_string(d$source_id) || !grepl("^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)*$", d$source_id) ||
      !source_string(d$representation) || !d$representation %in% c("json", "csv", "html") ||
      !source_string(d$absolute_request_url) || !identical(d$representation_method, "GET")) {
    stop("Invalid request descriptor.", call. = FALSE)
  }
  source_keys(d$request_headers, c("accept", "accept_encoding"), "negotiation headers")
  if (!setequal(names(d$request_headers), c("accept", "accept_encoding")) ||
      !all(vapply(d$request_headers, function(x) source_string(x) && !grepl("[[:cntrl:]]", x), logical(1))) ||
      !identical(identity$canonical, source_canonical_json(d)) ||
      !identical(identity$sha256, source_canonical_sha256(d))) stop("Invalid request identity checksum.", call. = FALSE)
  invisible(TRUE)
}

# Step II. No checker, schema decision, revision commit or snapshot publication.
source_http_abort <- function(code, kind = "protocol") {
  stop(structure(list(message = paste0("Source HTTP: ", code), call = NULL, code = code, kind = kind),
    class = c("source_http_error", "error", "condition")))
}

source_http_transport_error <- function(code, retryable = FALSE) {
  stop(structure(list(message = paste0("Source transport: ", code), call = NULL,
    code = code, retryable = retryable), class = c("source_http_transport_error", "error", "condition")))
}

# Header occurrences stay separate. Ambiguity is never resolved by concatenation.
source_http_header <- function(headers, name) {
  values <- headers[tolower(names(headers)) == tolower(name)]
  if (!length(values)) return(list(value = NULL, invalid = FALSE))
  valid <- length(values) == 1L && source_string(values[[1]]) &&
    !grepl("[[:cntrl:]]", values[[1]])
  list(value = if (valid) unname(values[[1]]) else NULL, invalid = !valid)
}

# Conservative IMF-fixdate parser, independent of LC_TIME. Obsolete HTTP date
# spellings are not reused as validators; invalid Retry-After uses bounded backoff.
source_http_date <- function(value) {
  pattern <- "^(Sun|Mon|Tue|Wed|Thu|Fri|Sat), [0-9]{2} (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} GMT$"
  if (!source_string(value) || !grepl(pattern, value)) return(NA_real_)
  month <- match(substr(value, 9L, 11L), c("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"))
  iso <- sprintf("%s-%02d-%sT%sZ", substr(value, 13L, 16L), month, substr(value, 6L, 7L), substr(value, 18L, 25L))
  if (!source_state_time(iso)) return(NA_real_)
  date <- as.POSIXct(iso, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  weekday <- match(substr(value, 1L, 3L), c("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")) - 1L
  if (as.POSIXlt(date, tz = "UTC")$wday != weekday) return(NA_real_)
  as.numeric(date)
}

source_http_validators <- function(headers) {
  etag <- source_http_header(headers, "etag")
  modified <- source_http_header(headers, "last-modified")
  if (!is.null(etag$value) && !grepl('^(W/)?"[^"[:cntrl:][:space:]]*"$', etag$value)) etag$invalid <- TRUE
  if (!is.null(modified$value) && is.na(source_http_date(modified$value))) modified$invalid <- TRUE
  list(etag_raw = if (etag$invalid) NULL else etag$value,
    last_modified_raw = if (modified$invalid) NULL else modified$value,
    invalid = c(if (etag$invalid) "etag", if (modified$invalid) "last-modified"))
}

source_http_retry_delay <- function(headers, attempt, clock, cap = 60) {
  fallback <- min(cap, 2^(attempt - 1L))
  header <- source_http_header(headers, "retry-after")$value
  if (is.null(header)) return(fallback)
  if (grepl("^[0-9]+$", header)) return(min(cap, as.numeric(header)))
  date <- source_http_date(header)
  if (is.na(date)) return(fallback)
  now <- clock()
  if (!source_state_time(now)) source_http_abort("invalid_clock", "argument")
  min(cap, max(0, date - as.numeric(as.POSIXct(now, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))))
}

# Read the entire checksum chain, but leave blob verification to the conditional
# policy. read_source_state() keeps its original strict content-check contract.
source_http_state_lookup <- function(config, identity) {
  records <- read_source_revisions(config, identity)
  if (length(records)) records[[length(records)]]$state_after else NULL
}

source_http_condition <- function(config, identity, state_lookup, reuse = TRUE) {
  state <- state_lookup(config, identity)
  result <- list(condition = NULL, content = NULL, diagnostic = NULL)
  if (is.null(state)) return(result)
  validate_source_state(state, identity)
  if (!reuse) return(result)
  content <- state$validated_content
  if (is.null(content) || !isTRUE(content$conditional_reuse_allowed)) return(result)
  verified <- verify_source_content(config, state$source_id, state$representation, content)
  if (!verified$valid) { result$diagnostic <- verified$code; return(result) }
  validators <- source_http_validators(list(etag = content$etag_raw, `last-modified` = content$last_modified_raw)[
    !vapply(list(content$etag_raw, content$last_modified_raw), is.null, logical(1))])
  if (length(validators$invalid)) result$diagnostic <- "invalid_validator"
  # An invalid ETag does not authorize falling back to another validator.
  if (!is.null(content$etag_raw)) {
    if (!is.null(validators$etag_raw)) result$condition <- list(name = "If-None-Match", value = validators$etag_raw)
  } else if (!is.null(validators$last_modified_raw)) {
    result$condition <- list(name = "If-Modified-Since", value = validators$last_modified_raw)
  }
  if (!is.null(result$condition)) result$content <- content[c("sha256", "bytes", "relative_path")]
  result
}

# Split only absolute transport URLs, retaining raw path/query and explicit port.
# httr2's exported url_parse/url_build normalize dot segments and query spelling;
# they cannot preserve the evidence needed by the 1A policy and this comparison.
# This splitter never replaces policy validation and never builds an identity.
source_http_url_components <- function(url) {
  if (!source_string(url)) return(NULL)
  pattern <- "^([A-Za-z][A-Za-z0-9+.-]*)://([^/?#]+)([^?#]*)(\\?[^#]*)?(#.*)?$"
  parts <- regmatches(url, regexec(pattern, url, perl = TRUE))[[1]]
  if (length(parts) != 6L) return(NULL)
  stats::setNames(as.list(parts[-1L]), c("scheme", "authority", "path", "query", "fragment"))
}

# Transport equivalence is deliberately narrower than URL canonicalization.
# Only scheme/host case and an empty root path may differ. Authority retains the
# explicit port; path, query and fragment spellings are otherwise exact.
source_http_urls_equivalent <- function(requested, effective, policy) {
  if (is.null(source_url_parts(requested, policy)) || is.null(source_url_parts(effective, policy))) return(FALSE)
  a <- source_http_url_components(requested); b <- source_http_url_components(effective)
  if (is.null(a) || is.null(b)) return(FALSE)
  comparable <- function(parts) {
    parts$scheme <- tolower(parts$scheme)
    parts$authority <- tolower(parts$authority) # Policy excludes credentials/IP literals.
    if (!nzchar(parts$path)) parts$path <- "/"
    parts
  }
  identical(comparable(a), comparable(b))
}

# Resolve relative references without normalizing away forbidden dot segments.
# The existing 1A policy and slug checks then validate the original absolute path.
source_http_redirect_identity <- function(identity, location, registry) {
  if (!source_string(location)) source_http_abort("invalid_redirect", "redirect")
  base <- source_http_url_components(identity$descriptor$absolute_request_url)
  if (is.null(base)) source_http_abort("invalid_redirect", "redirect")
  origin <- paste0(base$scheme, "://", base$authority)
  directory <- if (nzchar(base$path)) sub("[^/]*$", "", base$path) else "/"
  url <- if (grepl("^[A-Za-z][A-Za-z0-9+.-]*:", location)) location else
    if (startsWith(location, "//")) paste0(base$scheme, ":", location) else
    if (startsWith(location, "/")) paste0(origin, location) else
    if (startsWith(location, "?") || startsWith(location, "#")) paste0(origin, base$path, location) else
      paste0(origin, directory, location)
  d <- identity$descriptor
  source <- Filter(function(s) identical(s$source_id, d$source_id), registry$sources)[[1]]
  if (is.null(source_url_parts(url, registry$url_policy)) ||
      (source$role %in% c("complete_base", "thematic_subset") &&
        !identical(source_catalog_slug(url, d$representation, registry$url_policy), source$catalog_slug))) {
    source_http_abort("invalid_redirect", "redirect")
  }
  source_request_identity(d$source_id, d$representation, url, registry, d$request_headers)
}

source_http_curl_failure <- function(error) {
  cause <- if (inherits(error, "httr2_failure")) error$parent else error
  if (!inherits(cause, "curl_error")) stop(error)
  if (inherits(cause, "curl_error_operation_timedout")) source_http_transport_error("transport_timeout", TRUE)
  transient <- c("curl_error_couldnt_resolve_proxy", "curl_error_couldnt_resolve_host", "curl_error_couldnt_connect",
    "curl_error_send_error", "curl_error_recv_error", "curl_error_got_nothing", "curl_error_partial_file")
  source_http_transport_error("transport_failure", any(vapply(transient, function(cl) inherits(cause, cl), logical(1))))
}

# A single attempt only. Tests inject execute or replace this whole performer;
# production uses public httr2 APIs. Redirects and retries belong to our loop.
source_http_perform <- function(request, execute = httr2::req_perform) {
  req <- httr2::request(request$url)
  req <- httr2::req_method(req, request$method)
  req <- do.call(httr2::req_headers, c(list(req), request$headers))
  req <- httr2::req_user_agent(req, request$user_agent)
  req <- httr2::req_timeout(req, request$timeout)
  req <- httr2::req_options(req, followlocation = FALSE, maxredirs = 0L,
    nobody = identical(request$method, "HEAD"), http_content_decoding = FALSE)
  # httr2 1.2.2 classifies 429/503 even without req_retry(), and max_tries=1
  # alone still parses Retry-After. Explicitly disable classification through
  # the public API so only our outer loop owns retries, delay parsing and sleep.
  req <- httr2::req_retry(req, max_tries = 1L, retry_on_failure = FALSE,
    is_transient = function(resp) FALSE)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  resp <- tryCatch(execute(req, verbosity = 0), httr2_failure = source_http_curl_failure,
    curl_error = source_http_curl_failure)
  status <- httr2::resp_status(resp)
  body <- if (request$method == "GET" && status == 200L && httr2::resp_has_body(resp)) httr2::resp_body_raw(resp) else raw()
  list(status = status, headers = httr2::resp_headers(resp), url = httr2::resp_url(resp), body = body)
}

source_http_response <- function(response, request, policy) {
  if (!is.list(response) || !source_state_integer(response$status, 100, 599) ||
      !is.list(response$headers) || (length(response$headers) &&
        (is.null(names(response$headers)) || anyNA(names(response$headers)) || any(!nzchar(names(response$headers))))) ||
      !source_http_urls_equivalent(request$url, response$url, policy)) source_http_abort("invalid_response")
  # An executor must not silently follow a redirect or deliver a decoded text body.
  if (request$method == "GET" && response$status == 200L && !is.raw(response$body)) source_http_abort("body_not_raw")
  invisible(TRUE)
}

# Internal entry point. Requests are bounded to 3 attempts/hop, 5 redirects and
# one unconditional recovery chain. Only GET 200 can write a blob; no state IO
# other than reading revisions is performed here. No payload enters the result.
source_http_request <- function(config, identity, registry = load_source_registry(),
                                allow_download = FALSE, force_content = FALSE,
                                performer = source_http_perform, state_lookup = source_http_state_lookup,
                                clock = source_state_now, sleep = Sys.sleep, timeout = 30, max_attempts = 3L) {
  for (flag in list(allow_download, force_content)) if (!is.logical(flag) || length(flag) != 1L || is.na(flag)) source_http_abort("invalid_argument", "argument")
  if ((!allow_download && force_content) || !is.numeric(timeout) || length(timeout) != 1L ||
      is.na(timeout) || !is.finite(timeout) || timeout < 0.001 ||
      !source_state_integer(max_attempts, 1, 3)) source_http_abort("invalid_argument", "argument")
  validate_source_request_identity(identity)
  d <- identity$descriptor
  # Revalidate supplied identities against today's local policy, not only hash.
  checked <- source_request_identity(d$source_id, d$representation, d$absolute_request_url, registry, d$request_headers)
  if (!identical(checked$sha256, identity$sha256)) source_http_abort("invalid_argument", "argument")
  agent <- config$user_agent %||% "sampamaisagro/0.2"
  if (!source_string(agent) || grepl("[[:cntrl:]]", agent)) source_http_abort("invalid_argument", "argument")
  method <- if (allow_download) "GET" else "HEAD"
  result <- list(requested_identity = identity, identity = identity, method = method,
    requested_url = d$absolute_request_url, effective_url = d$absolute_request_url,
    http_status = NULL, attempts = 0L, requests = list(), redirects = list(),
    condition_sent = FALSE, condition = NULL, observed_etag_raw = NULL, observed_last_modified_raw = NULL,
    content = NULL, reused_content = NULL, cache_reused = NULL, retrieved_at = NULL,
    recovery = FALSE, content_changed = NA, diagnostics = list(), outcome = NULL, error = NULL)
  fail <- function(kind, code) {
    result$outcome <- if (kind == "state") "blocked" else paste0(kind, "_error")
    result$error <- list(kind = kind, code = code, decision = "block")
    result
  }
  run <- function() {
    recovery <- FALSE
    repeat {
      current <- result$identity
      eligible <- list(condition = NULL, content = NULL, diagnostic = NULL)
      # Every GET hop validates its own state; recovery disables only conditions.
      if (method == "GET") eligible <- source_http_condition(config, current, state_lookup,
        reuse = !force_content && !recovery)
      if (!is.null(eligible$diagnostic)) result$diagnostics[[length(result$diagnostics) + 1L]] <<-
        list(identity_sha256 = current$sha256, code = eligible$diagnostic)
      # One recovery chain, with one unconditional attempt per hop and no retries.
      limit <- if (recovery) 1L else max_attempts
      for (attempt in seq_len(limit)) {
        condition <- eligible$condition
        if (!is.null(condition)) {
          # Recheck before every retry too: no validator is sent on stale bytes.
          verified <- verify_source_content(config, d$source_id, d$representation, eligible$content)
          if (!verified$valid) { condition <- NULL; eligible$condition <- NULL }
        }
        headers <- list(Accept = d$request_headers$accept, `Accept-Encoding` = d$request_headers$accept_encoding)
        if (!is.null(condition)) headers[[condition$name]] <- condition$value
        request <- list(identity = current, method = method, url = current$descriptor$absolute_request_url,
          headers = headers, user_agent = agent, timeout = timeout, attempt = attempt)
        result$attempts <<- result$attempts + 1L
        result["condition"] <<- list(condition); result$condition_sent <<- !is.null(condition)
        result[c("http_status", "observed_etag_raw", "observed_last_modified_raw")] <<- list(NULL, NULL, NULL)
        entry <- list(identity_sha256 = current$sha256, method = method, url = request$url,
          attempt = attempt, condition = condition, recovery = recovery, status = NULL, error = NULL, sleep = NULL)
        entry_index <- length(result$requests) + 1L
        result$requests[[entry_index]] <<- entry
        response <- tryCatch(performer(request), source_http_transport_error = function(e) e)
        if (inherits(response, "source_http_transport_error")) {
          if (!response$code %in% c("transport_timeout", "transport_failure")) stop(response)
          entry$error <- response$code
          retry <- isTRUE(response$retryable) && attempt < limit
          if (retry) entry$sleep <- min(60, 2^(attempt - 1L))
          result$requests[[entry_index]] <<- entry
          if (!retry) return(fail("transport", response$code))
          sleep(entry$sleep); next
        }
        if (is.list(response) && source_state_integer(response$status, 100, 599)) {
          result$http_status <<- response$status
          entry$status <- response$status
          result$requests[[entry_index]] <<- entry
        }
        source_http_response(response, request, registry$url_policy)
        result$effective_url <<- response$url
        result$http_status <<- response$status
        validators <- source_http_validators(response$headers)
        result["observed_etag_raw"] <<- list(validators$etag_raw)
        result["observed_last_modified_raw"] <<- list(validators$last_modified_raw)
        if (length(validators$invalid)) result$diagnostics[[length(result$diagnostics) + 1L]] <<-
          list(identity_sha256 = current$sha256, code = "invalid_validator", headers = validators$invalid)
        entry$status <- response$status
        retry <- response$status %in% c(429L, 500L, 502L, 503L, 504L) && attempt < limit
        if (retry) entry$sleep <- source_http_retry_delay(response$headers, attempt, clock)
        result$requests[[entry_index]] <<- entry
        if (!retry) break
        sleep(entry$sleep)
      }
      status <- response$status
      if (status %in% c(301L, 302L, 303L, 307L, 308L)) {
        if (length(result$redirects) >= 5L) source_http_abort("redirect_limit", "redirect")
        location <- source_http_header(response$headers, "location")$value
        destination <- source_http_redirect_identity(current, location, registry)
        result$redirects[[length(result$redirects) + 1L]] <<- list(from = result$effective_url,
          to = destination$descriptor$absolute_request_url, status = status,
          from_identity = current$sha256, to_identity = destination$sha256)
        result$identity <<- destination; result$effective_url <<- destination$descriptor$absolute_request_url
        next
      }
      if (status == 304L) {
        if (method != "GET" || is.null(condition) || force_content || recovery || is.null(eligible$content)) source_http_abort("unsolicited_304")
        verified <- verify_source_content(config, d$source_id, d$representation, eligible$content)
        if (!verified$valid) {
          result$diagnostics[[length(result$diagnostics) + 1L]] <<- list(identity_sha256 = current$sha256, code = verified$code)
          recovery <- TRUE; result$recovery <<- TRUE
          next
        }
        result$reused_content <<- eligible$content
        result$outcome <<- "not_modified"
        return(result)
      }
      if (method == "HEAD" && status >= 200L && status < 300L) {
        result$outcome <<- "metadata"; return(result)
      }
      if (method == "GET" && status == 200L) {
        retrieved <- clock()
        if (!source_state_time(retrieved)) source_http_abort("invalid_clock", "argument")
        blob <- store_source_content(config, d$source_id, d$representation, response$body)
        result$content <<- blob$content; result$cache_reused <<- blob$reused
        result$retrieved_at <<- retrieved; result$outcome <<- "candidate"
        return(result)
      }
      if (status >= 400L) return(fail("http", "http_unavailable"))
      source_http_abort("unexpected_http_status")
    }
  }
  tryCatch(run(), source_http_error = function(e) fail(e$kind, e$code),
    source_state_block = function(e) fail("state", e$code))
}
