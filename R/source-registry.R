# Checkpoint 1A: local configuration and pure catalog reconciliation only.
source_asset_path <- function(...) {
  path <- system.file("sources", ..., package = "sampamaisrural")
  if (!nzchar(path)) path <- file.path(project_root(), "inst", "sources", ...)
  if (!file.exists(path)) stop("Source asset not found locally.", call. = FALSE)
  path
}

source_string <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)

source_keys <- function(x, allowed, context) {
  if (!is.list(x) || is.null(names(x)) || anyDuplicated(names(x)) ||
      any(!nzchar(names(x))) || any(!names(x) %in% allowed)) {
    stop("Invalid ", context, " fields.", call. = FALSE)
  }
}

load_source_registry <- function(path = source_asset_path("registry.yml")) {
  if (!file.exists(path)) stop("Registry must be a local file.", call. = FALSE)
  registry <- yaml::read_yaml(path, eval.expr = FALSE)
  validate_source_registry(registry)
  references <- unique(unlist(lapply(registry$sources, function(s)
    vapply(s$representations, `[[`, character(1), "contract")), use.names = FALSE))
  contracts <- stats::setNames(lapply(references, load_schema_contract), references)
  for (s in registry$sources) for (fmt in names(s$representations)) {
    if (!fmt %in% contracts[[s$representations[[fmt]]$contract]]$representations) {
      stop("Registry representation incompatible with associated contract.", call. = FALSE)
    }
  }
  registry
}

validate_source_registry <- function(registry) {
  source_keys(registry, c("registry_schema_version", "registry_revision", "url_policy", "sources"), "registry")
  if (!identical(registry$registry_schema_version, 1L) || !source_string(registry$registry_revision)) {
    stop("Unsupported registry version/revision.", call. = FALSE)
  }
  policy <- registry$url_policy
  source_keys(policy, c("schemes", "hosts", "ports", "allow_query"), "registry URL policy")
  if (!is.character(policy$schemes) || !length(policy$schemes) ||
      any(!policy$schemes %in% c("http", "https")) || !is.character(policy$hosts) || !length(policy$hosts) ||
      anyNA(policy$hosts) || any(!grepl("^[a-z0-9]+([.-][a-z0-9]+)*$", policy$hosts)) ||
      !is.numeric(policy$ports) || !length(policy$ports) || anyNA(policy$ports) ||
      any(policy$ports < 1 | policy$ports > 65535 | policy$ports != floor(policy$ports)) ||
      !is.logical(policy$allow_query) || length(policy$allow_query) != 1L || is.na(policy$allow_query)) {
    stop("Invalid registry URL policy.", call. = FALSE)
  }
  sources <- registry$sources
  if (!is.list(sources) || !length(sources)) stop("Empty registry sources.", call. = FALSE)
  ids <- vapply(sources, function(s) {
    if (!source_string(s$source_id) || !grepl("^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)*$", s$source_id)) {
      stop("Invalid source_id.", call. = FALSE)
    }
    s$source_id
  }, character(1))
  if (anyDuplicated(ids)) stop("Duplicate source_id.", call. = FALSE)
  slugs <- vapply(sources, function(s) if (is.null(s$catalog_slug)) "" else s$catalog_slug, character(1))
  if (anyDuplicated(slugs[nzchar(slugs)])) stop("Duplicate catalog_slug.", call. = FALSE)
  if (sum(vapply(sources, function(s) identical(s$role, "complete_base") && isTRUE(s$enabled), logical(1))) != 1L) {
    stop("Registry needs exactly one enabled complete_base.", call. = FALSE)
  }
  for (s in sources) {
    source_keys(s, c("source_id", "catalog_slug", "name", "role", "enabled", "overlaps_with", "representations"), "registry source")
    if (!source_string(s$name) || !source_string(s$role) ||
        !s$role %in% c("complete_base", "thematic_subset", "catalog", "terms") ||
        !is.logical(s$enabled) || length(s$enabled) != 1L || is.na(s$enabled)) {
      stop("Invalid registry source role/name/enabled.", call. = FALSE)
    }
    if (length(s$overlaps_with) && (!is.character(s$overlaps_with) || anyNA(s$overlaps_with) ||
        any(!s$overlaps_with %in% setdiff(ids, s$source_id)))) stop("Invalid overlap reference.", call. = FALSE)
    report <- s$role %in% c("complete_base", "thematic_subset")
    if (report && (!source_string(s$catalog_slug) || !grepl("^[a-z0-9]+(-[a-z0-9]+)*$", s$catalog_slug))) {
      stop("Invalid catalog_slug.", call. = FALSE)
    }
    if (!report && !is.null(s$catalog_slug)) stop("Support resource cannot have catalog_slug.", call. = FALSE)
    formats <- if (report) c("json", "csv") else if (s$role == "catalog") "json" else "html"
    source_keys(s$representations, formats, "registry representations")
    if (!setequal(names(s$representations), formats)) stop("Missing registry representation.", call. = FALSE)
    for (fmt in formats) {
      r <- s$representations[[fmt]]
      allowed <- c("parser", "contract", "filename")
      if (!report) allowed <- c(allowed, "endpoint_config", "default_url")
      source_keys(r, allowed, "registry representation")
      parser <- if (fmt == "csv") "semicolon_csv_v1" else if (fmt == "html") "html_document_v1" else
        if (report) "sampa_partners_json_v1" else "sampa_catalog_json_v1"
      if (!identical(r$parser, parser) || !source_string(r$contract) ||
          !grepl("^[a-z][a-z0-9-]*\\.yml$", r$contract)) stop("Invalid parser/contract reference.", call. = FALSE)
      if (!source_string(r$filename) || !grepl("^[a-z0-9_-]+\\.(json|csv|html)$", r$filename) ||
          (report && !identical(r$filename, paste0(s$catalog_slug, ".", fmt)))) {
        stop("Invalid representation filename.", call. = FALSE)
      }
      if (!report && (!identical(r$endpoint_config, paste0(s$role, "_url")) ||
          is.null(source_url_parts(r$default_url, policy)))) stop("Invalid support endpoint.", call. = FALSE)
    }
  }
  invisible(TRUE)
}

# Parsing does not perform HTTP. Reject ambiguous paths, credentials and fragments.
source_url_parts <- function(url, policy) {
  if (!source_string(url) || grepl("[[:space:]\\\\]", url) ||
      !grepl("^https?://", url, ignore.case = TRUE) ||
      grepl("%", sub("[?#].*$", "", url), fixed = TRUE)) return(NULL)
  # url_parse removes dot segments. Inspect the original path first; the
  # existing percent-encoding restriction above also rejects encoded variants.
  raw_path <- sub("^https?://[^/]*", "", sub("[?#].*$", "", url), ignore.case = TRUE)
  if (grepl("(^|/)\\.\\.?(/|$)", raw_path)) return(NULL)
  u <- tryCatch(httr2::url_parse(url), error = function(e) NULL)
  if (is.null(u)) return(NULL)
  port <- if (is.null(u$port)) if (tolower(u$scheme) == "https") 443L else 80L else suppressWarnings(as.numeric(u$port))
  if (!tolower(u$scheme) %in% policy$schemes || !tolower(u$hostname) %in% policy$hosts ||
      length(port) != 1L || is.na(port) || !port %in% policy$ports ||
      !is.null(u$username) || !is.null(u$password) || !is.null(u$fragment) ||
      (!isTRUE(policy$allow_query) && length(u$query)) || is.null(u$path) ||
      grepl("%|(^|/)\\.\\.?(/|$)", u$path)) return(NULL)
  u
}

source_catalog_slug <- function(url, format, policy) {
  u <- source_url_parts(url, policy)
  if (is.null(u)) return(NA_character_)
  filename <- basename(u$path)
  if (!grepl(paste0("^[a-z0-9]+(-[a-z0-9]+)*\\.", format, "$"), filename)) return(NA_character_)
  sub(paste0("\\.", format, "$"), "", filename)
}

reconcile_source_catalog <- function(registry, catalog) {
  validate_source_registry(registry)
  issues <- list(); mapping <- list()
  add <- function(code, path, expected, observed, severity = "breaking") {
    issues[[length(issues) + 1L]] <<- data.frame(code, path, expected, observed, severity)
  }
  if (!identical(source_node_type(catalog), "array")) {
    add("invalid_catalog", "$", "array", source_node_type(catalog))
    catalog <- list()
  }
  reports <- Filter(function(s) s$role %in% c("complete_base", "thematic_subset"), registry$sources)
  known <- vapply(reports, `[[`, character(1), "catalog_slug")
  seen <- character()
  for (i in seq_along(catalog)) {
    entry <- catalog[[i]]; path <- paste0("$/", i)
    if (!identical(source_node_type(entry), "object") || anyDuplicated(names(entry))) {
      add("invalid_catalog_entry", path, "object with unique keys", source_node_type(entry)); next
    }
    slugs <- stats::setNames(rep(NA_character_, 2), c("json", "csv"))
    for (fmt in names(slugs)) {
      if (!source_string(entry[[fmt]])) {
        add(paste0("missing_", fmt), path, "representation URL", "absent or invalid")
      } else {
        slugs[[fmt]] <- source_catalog_slug(entry[[fmt]], fmt, registry$url_policy)
        if (is.na(slugs[[fmt]])) add(paste0("invalid_", fmt, "_url"), path, "permitted unambiguous URL", "invalid or not permitted")
      }
    }
    slug <- slugs[["json"]]
    if (is.na(slug)) next
    if (slug %in% seen) add("duplicate_catalog_slug", path, "unique catalog_slug", slug)
    seen <- c(seen, slug)
    if (!is.na(slugs[["csv"]]) && slug != slugs[["csv"]]) {
      add("representation_slug_mismatch", path, slug, slugs[["csv"]]); next
    }
    k <- match(slug, known)
    if (is.na(k)) { add("unknown_source", path, "registered source", slug, "coverage"); next }
    s <- reports[[k]]
    if (anyNA(slugs)) next
    for (fmt in names(slugs)) mapping[[length(mapping) + 1L]] <- data.frame(
      source_id = s$source_id, catalog_slug = slug, representation = fmt, enabled = s$enabled,
      catalog_index = i, url = entry[[fmt]], filename = s$representations[[fmt]]$filename)
  }
  for (s in reports) if (isTRUE(s$enabled) && !s$catalog_slug %in% seen) {
    add("missing_source", "$", s$source_id, "absent")
  }
  issue_table <- if (length(issues)) do.call(rbind, issues) else data.frame(
    code = character(), path = character(), expected = character(), observed = character(), severity = character())
  blocked <- any(issue_table$severity == "breaking")
  list(classification = if (blocked) "breaking" else if (nrow(issue_table)) "coverage_drift" else "valid",
    decision = if (blocked) "block" else if (nrow(issue_table)) "review" else "allow",
    mapping = if (length(mapping)) do.call(rbind, mapping) else data.frame(source_id = character(),
      catalog_slug = character(), representation = character(), enabled = logical(), catalog_index = integer(),
      url = character(), filename = character()), issues = issue_table)
}
