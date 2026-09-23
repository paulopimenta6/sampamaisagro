# All functions in this module are internal and operate on supplied local inputs.
source_node_type <- function(x) {
  if (is.null(x) || (is.atomic(x) && length(x) == 1L && is.na(x))) return("null")
  if (is.list(x) && !is.data.frame(x)) return(if (is.null(names(x))) "array" else "object")
  if (length(x) != 1L || !is.null(attributes(x))) return("unsupported")
  if (is.character(x)) return("string")
  if (is.logical(x)) return("boolean")
  if (is.numeric(x) && is.finite(x)) return("number")
  "unsupported"
}

source_path <- function(parent, key) {
  # ~2 reserves literal '*' field names, distinct from the array wildcard /*.
  key <- gsub("*", "~2", gsub("/", "~1", gsub("~", "~0", key, fixed = TRUE), fixed = TRUE), fixed = TRUE)
  paste0(parent, "/", key)
}

source_sort <- function(x) sort(unique(enc2utf8(x)), method = "radix")

read_source_payload <- function(path, representation = c("json", "csv", "html")) {
  representation <- match.arg(representation)
  if (!source_string(path) || !file.exists(path) || dir.exists(path)) {
    stop("Source input must be a local file.", call. = FALSE)
  }
  if (representation == "csv") {
    x <- tryCatch(suppressWarnings(readr::read_delim(path, delim = ";", quote = '"',
      col_types = readr::cols(.default = readr::col_character()), locale = readr::locale(encoding = "UTF-8"),
      na = character(), trim_ws = FALSE, name_repair = "minimal", skip_empty_rows = FALSE,
      show_col_types = FALSE, progress = FALSE)), error = function(e) NULL)
    if (is.null(x) || !ncol(x) || any(!nzchar(names(x))) || anyDuplicated(names(x)) || nrow(readr::problems(x))) {
      stop("Invalid CSV structure or parsing problems.", call. = FALSE)
    }
    return(as.data.frame(x, stringsAsFactors = FALSE))
  }
  text <- paste(readLines(path, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  if (representation == "html") return(text)
  # parse_json never interprets a text value as a URL (unlike fromJSON).
  tryCatch(jsonlite::parse_json(text, simplifyVector = FALSE),
    error = function(e) stop("Invalid JSON structure.", call. = FALSE))
}

load_schema_contract <- function(path) {
  if (!source_string(path)) stop("Schema contract must be a local file.", call. = FALSE)
  if (!file.exists(path) && source_string(path) && grepl("^[a-z][a-z0-9-]*\\.yml$", path)) {
    path <- source_asset_path("contracts", path)
  }
  if (!file.exists(path)) stop("Schema contract must be a local file.", call. = FALSE)
  contract <- yaml::read_yaml(path, eval.expr = FALSE)
  validate_schema_contract(contract)
  contract
}

source_records_keys <- function(path) {
  if (is.null(path) || identical(path, "")) return(character())
  if (!source_string(path) || !startsWith(path, "/")) stop("Invalid records_path.", call. = FALSE)
  keys <- strsplit(substring(path, 2), "/", fixed = TRUE)[[1]]
  # Decode the JSON pointer once, before source_path applies profile escaping.
  gsub("~0", "~", gsub("~1", "/", keys, fixed = TRUE), fixed = TRUE)
}

source_records_schema <- function(contract) {
  node <- contract$schema
  path <- contract$records_path
  if (is.null(path)) return(NULL)
  for (key in source_records_keys(path)) {
    if (!"object" %in% node$types || !key %in% names(node$properties)) stop("Invalid records_path.", call. = FALSE)
    node <- node$properties[[key]]
  }
  if (!identical(node$types, "array")) stop("records_path must identify an array.", call. = FALSE)
  node
}

validate_schema_contract <- function(contract) {
  source_keys(contract, c("contract_schema_version", "contract_id", "version", "representations",
    "records_path", "schema", "csv_projection"), "schema contract")
  if (!identical(contract$contract_schema_version, 1L) || !source_string(contract$contract_id) ||
      !is.numeric(contract$version) || length(contract$version) != 1L || is.na(contract$version) ||
      contract$version < 1 || contract$version != floor(contract$version)) stop("Invalid contract version/id.", call. = FALSE)
  if (!is.character(contract$representations) || !length(contract$representations) ||
      anyNA(contract$representations) || any(!contract$representations %in% c("json", "csv", "html"))) {
    stop("Invalid contract representations.", call. = FALSE)
  }
  if (!"records_path" %in% names(contract)) stop("Missing records_path declaration.", call. = FALSE)
  check <- function(node) {
    source_keys(node, c("types", "nullable", "required", "properties", "items", "additional_fields",
      "min_items", "min_length", "pattern", "preferred_types"), "schema node")
    types <- node$types
    if (!is.character(types) || !length(types) || anyNA(types) || anyDuplicated(types) ||
        any(!types %in% c("object", "array", "string", "number", "boolean"))) stop("Invalid schema types.", call. = FALSE)
    for (flag in intersect(c("nullable", "required"), names(node))) {
      if (!is.logical(node[[flag]]) || length(node[[flag]]) != 1L || is.na(node[[flag]])) {
        stop("Invalid schema flag.", call. = FALSE)
      }
    }
    if (!is.null(node$preferred_types) && (!is.character(node$preferred_types) ||
        !length(node$preferred_types) || anyNA(node$preferred_types) || any(!node$preferred_types %in% types))) {
      stop("Invalid preferred_types.", call. = FALSE)
    }
    if ("object" %in% types) {
      if (!source_string(node$additional_fields) || !node$additional_fields %in% c("allow_and_report", "forbid")) {
        stop("Invalid additional_fields policy.", call. = FALSE)
      }
      if (!is.list(node$properties) || is.null(names(node$properties)) || anyDuplicated(names(node$properties))) {
        stop("Invalid schema properties.", call. = FALSE)
      }
      lapply(node$properties, check)
    } else if (!is.null(node$properties) || !is.null(node$additional_fields)) stop("Object-only schema options.", call. = FALSE)
    if ("array" %in% types) {
      if (is.null(node$items)) stop("Array schema needs items.", call. = FALSE)
      check(node$items)
    } else if (!is.null(node$items) || !is.null(node$min_items)) stop("Array-only schema options.", call. = FALSE)
    for (limit in intersect(c("min_items", "min_length"), names(node))) {
      n <- node[[limit]]
      if (!is.numeric(n) || length(n) != 1L || is.na(n) || n < 0 || n != floor(n)) stop("Invalid schema minimum.", call. = FALSE)
    }
    if ((!is.null(node$pattern) || !is.null(node$min_length)) && !"string" %in% types) stop("String-only schema options.", call. = FALSE)
    if (!is.null(node$pattern)) {
      if (!source_string(node$pattern)) stop("Invalid schema pattern.", call. = FALSE)
      tryCatch(grepl(node$pattern, "", perl = TRUE), error = function(e) stop("Invalid schema pattern.", call. = FALSE))
    }
    invisible(NULL)
  }
  check(contract$schema)
  records <- source_records_schema(contract)
  if ("csv" %in% contract$representations) {
    p <- contract$csv_projection
    source_keys(p, c("delimiter", "encoding", "null_value", "boolean_true", "boolean_false", "array_separator", "numeric_fields"), "CSV projection")
    if (is.null(records) || !identical(records$items$types, "object") ||
        !identical(p$delimiter, ";") || !identical(p$encoding, "UTF-8") || !identical(p$null_value, "") ||
        !source_string(p$boolean_true) || !source_string(p$boolean_false) || identical(p$boolean_true, p$boolean_false) ||
        !source_string(p$array_separator) || !is.character(p$numeric_fields) || anyNA(p$numeric_fields) ||
        any(!p$numeric_fields %in% names(records$items$properties))) stop("Invalid CSV projection.", call. = FALSE)
    for (key in p$numeric_fields) if (!"number" %in% records$items$properties[[key]]$types) {
      stop("Numeric CSV projection needs a compatible field type.", call. = FALSE)
    }
  }
  invisible(TRUE)
}

profile_source_schema <- function(payload) {
  nodes <- new.env(parent = emptyenv())
  touch <- function(path, type = NULL) {
    n <- if (exists(path, nodes, inherits = FALSE)) get(path, nodes) else
      list(path = path, types = character(), observations = 0L, nulls = 0L, object_observations = 0L)
    if (!is.null(type)) {
      n$observations <- n$observations + 1L
      if (type == "null") n$nulls <- n$nulls + 1L else n$types <- source_sort(c(n$types, type))
      if (type == "object") n$object_observations <- n$object_observations + 1L
    }
    assign(path, n, nodes)
  }
  walk <- function(x, path) {
    type <- source_node_type(x); touch(path, type)
    if (type == "object") for (i in seq_along(x)) walk(x[[i]], source_path(path, names(x)[i]))
    if (type == "array") {
      item_path <- paste0(path, "/*"); touch(item_path)
      for (item in x) walk(item, item_path)
    }
  }
  walk(payload, "$")
  paths <- source_sort(ls(nodes, all.names = TRUE))
  list(profile_version = 1L, nodes = lapply(paths, function(path) get(path, nodes)))
}

schema_fingerprint <- function(profile) {
  ordered <- profile$nodes[order(vapply(profile$nodes, `[[`, character(1), "path"), method = "radix")]
  structure <- lapply(ordered, function(n) list(path = n$path, types = source_sort(n$types)))
  canonical <- as.character(jsonlite::toJSON(list(fingerprint_version = 1L, nodes = structure),
    auto_unbox = TRUE, null = "null", pretty = FALSE))
  unknown <- vapply(Filter(function(n) !length(n$types), ordered), `[[`, character(1), "path")
  observed <- digest::digest(enc2utf8(canonical), algo = "sha256", serialize = FALSE)
  list(sha256 = if (length(unknown)) NA_character_ else observed, observed_sha256 = observed,
    canonical = canonical, evidence_quality = if (length(unknown)) "partial" else "complete",
    unknown_paths = unknown)
}

source_empty_changes <- function() data.frame(path = character(), code = character(), expected = character(),
  observed = character(), severity = character(), stringsAsFactors = FALSE)

source_record_count <- function(profile, contract) {
  if (is.null(contract$records_path)) return(NA_integer_)
  path <- Reduce(source_path, source_records_keys(contract$records_path), init = "$")
  path <- paste0(path, "/*")
  hit <- Filter(function(n) identical(n$path, path), profile$nodes)
  if (!length(hit)) return(NA_integer_)
  hit[[1]]$observations
}

compare_schema_to_contract <- function(profile, contract, source_id = NA_character_, representation = "json", reference = NULL) {
  validate_schema_contract(contract)
  changes <- list()
  add <- function(path, code, expected, observed, severity) {
    changes[[length(changes) + 1L]] <<- data.frame(path, code, expected, observed, severity)
  }
  indexed <- stats::setNames(profile$nodes, vapply(profile$nodes, `[[`, character(1), "path"))
  visit <- function(schema, path, parent_count = 1L) {
    observed <- indexed[[path]]
    n <- if (is.null(observed)) 0L else observed$observations
    if (isTRUE(schema$required) && n < parent_count) add(path, "required_field_missing", "present in every parent", "absent in some or all parents", "breaking")
    if (is.null(observed)) return(invisible(NULL))
    bad <- setdiff(observed$types, schema$types)
    if (length(bad)) add(path, "incompatible_type", paste(schema$types, collapse = "|"), paste(bad, collapse = "|"), "breaking")
    if (observed$nulls && !isTRUE(schema$nullable)) add(path, "null_not_allowed", "non-null", "null", "breaking")
    if (!is.null(schema$preferred_types)) {
      alternative <- intersect(setdiff(observed$types, schema$preferred_types), schema$types)
      if (length(alternative)) add(path, "compatible_type_variation", paste(schema$preferred_types, collapse = "|"), paste(alternative, collapse = "|"), "suspicious")
    }
    if ("object" %in% schema$types && "object" %in% observed$types) {
      for (key in names(schema$properties)) visit(schema$properties[[key]], source_path(path, key), observed$object_observations)
      prefix <- paste0(path, "/")
      children <- names(indexed)[startsWith(names(indexed), prefix)]
      children <- children[!grepl("/", substring(children, nchar(prefix) + 1L), fixed = TRUE)]
      # In an object/array union, the item wildcard is not an object property.
      children <- setdiff(children, paste0(path, "/*"))
      known <- vapply(names(schema$properties), function(key) source_path(path, key), character(1))
      for (child in setdiff(children, known)) add(child, "additional_field", "not declared", "additional structural field",
        if (schema$additional_fields == "forbid") "breaking" else "additive")
    }
    if ("array" %in% schema$types && "array" %in% observed$types) visit(schema$items, paste0(path, "/*"), 0L)
    invisible(NULL)
  }
  visit(contract$schema, "$")
  count <- source_record_count(profile, contract)
  if (!is.null(reference) && (is.null(contract$records_path) || (!is.na(count) && count > 0L))) {
    previous <- stats::setNames(reference$nodes, vapply(reference$nodes, `[[`, character(1), "path"))
    for (path in intersect(names(previous), names(indexed))) {
      old <- previous[[path]]$types; new <- indexed[[path]]$types
      if (length(old) && length(new) && !setequal(old, new)) {
        add(path, "observed_type_change", paste(old, collapse = "|"), paste(new, collapse = "|"), "suspicious")
      }
    }
    for (path in setdiff(names(previous), names(indexed))) {
      # A disappeared child is evidence only if its parent is observed nonempty.
      parent <- sub("/[^/]*$", "", path)
      current_parent <- indexed[[parent]]
      if (!is.null(current_parent) && current_parent$observations > current_parent$nulls &&
          "object" %in% current_parent$types && length(previous[[path]]$types)) {
        add(path, "optional_field_disappeared", "previously observed field", "absent", "suspicious")
      }
    }
  }
  table <- if (length(changes)) unique(do.call(rbind, changes)) else source_empty_changes()
  source_schema_result(profile, contract, source_id, representation, table)
}

source_schema_result <- function(profile, contract, source_id, representation, changes) {
  fingerprint <- schema_fingerprint(profile)
  count <- source_record_count(profile, contract)
  partial <- fingerprint$evidence_quality == "partial" || (!is.na(count) && count == 0L)
  classification <- if (any(changes$severity == "breaking")) "breaking" else
    if (any(changes$severity == "suspicious")) "suspicious" else
    if (any(changes$severity == "additive")) "additive" else if (partial) "insufficient_evidence" else "valid"
  list(source_id = source_id, representation = representation, contract_id = contract$contract_id,
    contract_version = contract$version, classification = classification,
    decision = if (classification == "breaking") "block" else if (classification == "suspicious") "warn" else "allow",
    changes = changes, evidence = list(quality = if (partial) "partial" else "complete", record_count = count,
      observed_paths = length(profile$nodes), unknown_paths = fingerprint$unknown_paths), fingerprint = fingerprint)
}

validate_source_payload <- function(payload, contract, source_id = NA_character_, representation = "json", reference = NULL) {
  validate_schema_contract(contract)
  if (!representation %in% contract$representations || representation == "csv") {
    stop("Use validate_source_pair for the declared CSV projection.", call. = FALSE)
  }
  profile <- profile_source_schema(payload)
  result <- compare_schema_to_contract(profile, contract, source_id, representation, reference)
  extra <- list()
  add <- function(path, code, expected, observed) {
    extra[[length(extra) + 1L]] <<- data.frame(path, code, expected, observed, severity = "breaking")
  }
  # Per-instance constraints cannot be inferred from aggregate type unions/counts.
  walk <- function(x, schema, path) {
    type <- source_node_type(x)
    if (type == "unsupported") add(path, "unsupported_value", "JSON-compatible value", "unsupported R value")
    if (type == "object") {
      if (anyDuplicated(names(x)) || any(!nzchar(names(x)))) add(path, "invalid_object_keys", "unique nonempty keys", "ambiguous keys")
      if (!is.null(schema) && "object" %in% schema$types) {
        for (key in names(schema$properties)) if (isTRUE(schema$properties[[key]]$required) && !key %in% names(x)) {
          add(source_path(path, key), "required_field_missing", "field present", "absent")
        }
      }
      for (i in seq_along(x)) walk(x[[i]], if (is.null(schema)) NULL else schema$properties[[names(x)[i]]], source_path(path, names(x)[i]))
    }
    if (type == "array") {
      if (!is.null(schema$min_items) && length(x) < schema$min_items) add(path, "too_few_items", "minimum items", "insufficient items")
      for (item in x) walk(item, if (is.null(schema)) NULL else schema$items, paste0(path, "/*"))
    }
    if (type == "string" && !is.null(schema)) {
      if (!is.null(schema$min_length) && nchar(x) < schema$min_length) add(path, "string_too_short", "minimum length", "too short")
      if (!is.null(schema$pattern) && !grepl(schema$pattern, x, perl = TRUE)) add(path, "pattern_mismatch", "declared structural pattern", "not matched")
    }
  }
  walk(payload, contract$schema, "$")
  if (length(extra)) result <- source_schema_result(profile, contract, source_id, representation,
    unique(rbind(result$changes, do.call(rbind, extra))))
  result
}

source_records <- function(payload, contract) {
  if (is.null(contract$records_path) || identical(contract$records_path, "")) return(payload)
  for (key in source_records_keys(contract$records_path)) payload <- payload[[key]]
  payload
}

validate_source_pair <- function(payload, csv, contract, source_id = NA_character_) {
  validate_schema_contract(contract)
  if (!"csv" %in% contract$representations) stop("Contract has no CSV projection.", call. = FALSE)
  if (is.character(csv) && length(csv) == 1L) csv <- read_source_payload(csv, "csv")
  if (!is.data.frame(csv) || !ncol(csv) || any(!nzchar(names(csv))) || anyDuplicated(names(csv)) ||
      !all(vapply(csv, is.character, logical(1))) || anyNA(csv)) stop("Invalid CSV table; use read_source_payload.", call. = FALSE)
  validation <- validate_source_payload(payload, contract, source_id)
  records <- if (validation$decision != "block") source_records(payload, contract) else list()
  result <- list(source_id = source_id, representation = "json/csv", contract_id = contract$contract_id,
    contract_version = contract$version, classification = "inconsistent_under_projection", decision = "block",
    json_records = if (validation$decision == "block") NA_integer_ else length(records), csv_records = nrow(csv),
    projection_lossy = TRUE, limitations = c("null and empty string coincide", "concatenated arrays are not reconstructed"),
    compared_fields = character(), unsupported_fields = character(), divergent_fields = character(),
    row_multiset_matches = NA, comparison_coverage = list(total_fields = ncol(csv), compared_fields = 0L,
      unsupported_fields = 0L), issues = character(), source_classification = validation$classification)
  if (validation$decision == "block") { result$issues <- "invalid_json_schema"; return(result) }
  fields <- source_records_schema(contract)$items$properties
  required <- names(Filter(function(f) isTRUE(f$required), fields))
  json_fields <- unique(unlist(lapply(records, names), use.names = FALSE))
  if (any(!required %in% names(csv)) || (length(records) && !setequal(json_fields, names(csv)))) {
    result$issues <- "incompatible_columns"; return(result)
  }
  if (length(records) != nrow(csv)) { result$issues <- "different_record_counts"; return(result) }
  p <- contract$csv_projection
  columns <- source_sort(names(csv))
  project <- function(value) {
    type <- source_node_type(value)
    if (type == "null") return(p$null_value)
    if (type == "boolean") return(if (value) p$boolean_true else p$boolean_false)
    if (type == "string") return(value)
    if (type == "number") return(sprintf("%.17g", value))
    if (type == "array" && all(vapply(value, function(x) source_node_type(x) %in% c("string", "number", "boolean"), logical(1)))) {
      return(paste(vapply(value, project, character(1)), collapse = p$array_separator))
    }
    NA_character_ # No declared projection; never compare this placeholder.
  }
  projected <- lapply(records, function(row) stats::setNames(lapply(columns, function(key) project(row[[key]])), columns))
  result$unsupported_fields <- columns[vapply(columns, function(key)
    any(vapply(projected, function(row) is.na(row[[key]]), logical(1))), logical(1))]
  columns <- setdiff(columns, result$unsupported_fields)
  result$compared_fields <- columns
  result$comparison_coverage$compared_fields <- length(columns)
  result$comparison_coverage$unsupported_fields <- length(result$unsupported_fields)
  if (length(result$unsupported_fields)) {
    result$issues <- "unsupported_projection_shape"
    result$limitations <- c(result$limitations, "unsupported fields excluded from comparison; see unsupported_fields")
  }
  token <- function(values) {
    values <- lapply(values, function(value) list(type = "text", value = value))
    for (key in intersect(names(values), p$numeric_fields)) {
      value <- values[[key]]$value
      if (grepl("^[+-]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][+-]?[0-9]+)?$", value)) {
        number <- suppressWarnings(as.numeric(value))
        if (is.finite(number)) values[[key]] <- list(type = "number", value = sprintf("%a", if (number == 0) 0 else number))
      }
    }
    as.character(jsonlite::toJSON(unname(values), auto_unbox = TRUE))
  }
  json_tokens <- vapply(projected, function(row) token(row[columns]), character(1))
  csv_tokens <- vapply(seq_len(nrow(csv)), function(i) token(as.list(csv[i, columns, drop = FALSE])), character(1))
  same_multiset <- function(a, b) identical(sort(a, method = "radix"), sort(b, method = "radix"))
  result$row_multiset_matches <- same_multiset(json_tokens, csv_tokens)
  if (!result$row_multiset_matches) {
    result$issues <- c(result$issues, "different_projected_row_multisets")
    # Marginal differences identify fields without logging values. Joint row
    # differences can still exist when every individual field multiset agrees.
    result$divergent_fields <- columns[!vapply(columns, function(key) same_multiset(
      vapply(projected, function(row) token(row[key]), character(1)),
      vapply(seq_len(nrow(csv)), function(i) token(as.list(csv[i, key, drop = FALSE])), character(1))), logical(1))]
    if (!length(result$divergent_fields)) result$issues <- c(result$issues, "different_projected_row_associations")
  } else if (length(result$unsupported_fields)) {
    result$classification <- "insufficient_evidence"; result$decision <- "warn"
  } else {
    result$classification <- "consistent_under_projection"
    result$decision <- if (validation$decision == "warn") "warn" else "allow"
  }
  result
}
