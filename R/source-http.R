# Checkpoint 1B, step I: pure request identities only. No HTTP transport.
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
