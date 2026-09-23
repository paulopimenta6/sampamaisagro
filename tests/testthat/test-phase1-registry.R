test_that("1A registry is packaged, versioned and keeps one complete base", {
  registry <- load_source_registry()
  expect_true(validate_source_registry(registry))
  roles <- vapply(registry$sources, `[[`, character(1), "role")
  expect_equal(sum(roles == "complete_base"), 1)
  expect_equal(sum(roles == "thematic_subset"), 13)
  expect_equal(sum(roles %in% c("catalog", "terms")), 2)
  for (s in registry$sources) for (rep in s$representations) {
    expect_silent(load_schema_contract(rep$contract))
  }
  report <- registry$sources[roles == "complete_base"][[1]]
  expect_identical(report$catalog_slug, "base-completa-sampa-rural")
  expect_setequal(names(report$representations), c("json", "csv"))
  expect_false(any(c("report_id", "etag", "last_checked_at") %in% names(report)))
  expect_false(any(vapply(registry$sources[roles %in% c("complete_base", "thematic_subset")],
    function(s) any(vapply(s$representations, function(r) "url" %in% names(r), logical(1))), logical(1))))
})

test_that("1A registry rejects duplicate and ambiguous identities", {
  r <- phase1_registry(); r$sources[[2]]$source_id <- r$sources[[1]]$source_id
  expect_error(validate_source_registry(r), "source_id")
  r <- phase1_registry(); r$sources[[2]]$catalog_slug <- r$sources[[1]]$catalog_slug
  expect_error(validate_source_registry(r), "catalog_slug")
  r <- phase1_registry(); r$sources[[1]]$enabled <- FALSE
  expect_error(validate_source_registry(r), "complete_base")
  r <- phase1_registry(); r$sources[[2]]$role <- "complete_base"
  expect_error(validate_source_registry(r), "complete_base")
  r <- phase1_registry(); r$sources[[1]]$etag <- "not configuration"
  expect_error(validate_source_registry(r), "registry")
  r <- phase1_registry(); r$sources[[2]]$representations$json$filename <- "../escape.json"
  expect_error(validate_source_registry(r), "filename")
})

test_that("1A pure reconciliation discovers URLs independently of display names", {
  v02_forbid_http()
  r <- phase1_registry(); catalog <- phase1_json("catalog.json")
  original <- r
  result <- reconcile_source_catalog(r, catalog)
  expect_identical(result$classification, "valid")
  expect_equal(nrow(result$mapping), 4)
  expect_setequal(result$mapping$source_id, c("demo.base", "demo.subset"))
  expect_setequal(result$mapping$representation, c("json", "csv"))
  catalog[[1]]$name <- "Nome totalmente diferente"
  catalog[[1]]$json <- "https://example.invalid/new/path/base-sintetica.json?revision=2"
  next_result <- reconcile_source_catalog(r, catalog)
  expect_identical(next_result$classification, "valid")
  expect_identical(next_result$mapping$source_id, result$mapping$source_id)
  expect_true(any(next_result$mapping$url == catalog[[1]]$json))
  expect_identical(r, original)
})

test_that("1A coverage and malformed representations have explicit diagnostics", {
  r <- phase1_registry()
  missing <- reconcile_source_catalog(r, phase1_json("catalog-missing.json"))
  expect_true("missing_source" %in% missing$issues$code)
  expect_identical(missing$decision, "block")
  extra <- reconcile_source_catalog(r, phase1_json("catalog-additional.json"))
  expect_true("unknown_source" %in% extra$issues$code)
  expect_identical(extra$classification, "coverage_drift")
  expect_identical(extra$decision, "review")
  mismatch <- reconcile_source_catalog(r, phase1_json("catalog-slug-mismatch.json"))
  expect_true("representation_slug_mismatch" %in% mismatch$issues$code)
  expect_identical(mismatch$decision, "block")
  for (fmt in c("json", "csv")) {
    c <- phase1_json("catalog.json"); c[[1]][[fmt]] <- NULL
    out <- reconcile_source_catalog(r, c)
    expect_true(paste0("missing_", fmt) %in% out$issues$code)
    expect_identical(out$decision, "block")
  }
  c <- phase1_json("catalog.json"); c[[3]] <- c[[1]]
  expect_true("duplicate_catalog_slug" %in% reconcile_source_catalog(r, c)$issues$code)
})

test_that("1A URL policy rejects unsafe or ambiguous catalog entries without HTTP", {
  v02_forbid_http()
  urls <- c("http://example.invalid/base-sintetica.json", "https://example.invalid.evil/base-sintetica.json",
    "https://user:secret@example.invalid/base-sintetica.json", "file:///tmp/base-sintetica.json",
    "https://example.invalid/base-sintetica.json#fragment", "https://example.invalid/base%2Fsintetica.json",
    "https://example.invalid:8443/base-sintetica.json", "not a URL")
  for (url in urls) {
    c <- phase1_json("catalog.json"); c[[1]]$json <- url
    result <- reconcile_source_catalog(phase1_registry(), c)
    expect_identical(result$decision, "block")
    expect_true("invalid_json_url" %in% result$issues$code)
    expect_false(grepl("secret", paste(result$issues$observed, collapse = " ")))
  }
  expect_error(read_source_payload("https://example.invalid/data.json", "json"), "local")
})

test_that("1A URL policy rejects original dot segments before parser normalization", {
  v02_forbid_http()
  r <- phase1_registry()
  paths <- c("/x/../base-sintetica", "/./base-sintetica", "/x/./base-sintetica",
    "/x/%2e%2E/base-sintetica", "/%2E/base-sintetica", "/x/.%2e/base-sintetica",
    "/x/%252e%252e/base-sintetica", "/x%2f..%2fbase-sintetica")
  for (path in paths) for (fmt in c("json", "csv")) {
    url <- paste0("https://example.invalid", path, ".", fmt)
    expect_null(source_url_parts(url, r$url_policy), info = url)
    catalog <- phase1_json("catalog.json"); catalog[[1]][[fmt]] <- url
    out <- reconcile_source_catalog(r, catalog)
    expect_identical(out$decision, "block", info = url)
    expect_true(paste0("invalid_", fmt, "_url") %in% out$issues$code, info = url)
    expect_false(url %in% out$mapping$url, info = url)
  }
  for (path in c("/x/.", "/x/..")) {
    expect_null(source_url_parts(paste0("https://example.invalid", path), r$url_policy))
  }
})

test_that("1A legitimate directories, queries and catalog identities stay unchanged", {
  v02_forbid_http()
  r <- phase1_registry()
  for (path in c("/exports/v1", "/exports/.well-known", "/exports/v1.2")) {
    catalog <- phase1_json("catalog.json")
    for (fmt in c("json", "csv")) {
      catalog[[1]][[fmt]] <- paste0("https://example.invalid", path, "/base-sintetica.", fmt,
        "?revision=2&value=../x&encoded=%2E%2E")
      expect_identical(source_catalog_slug(catalog[[1]][[fmt]], fmt, r$url_policy), "base-sintetica")
    }
    out <- reconcile_source_catalog(r, catalog)
    expect_identical(out$classification, "valid")
    expect_identical(out$decision, "allow")
    base <- out$mapping[out$mapping$source_id == "demo.base", ]
    expect_identical(base$catalog_slug, rep("base-sintetica", 2))
    expect_setequal(base$url, c(catalog[[1]]$json, catalog[[1]]$csv))
    policy <- r$url_policy; policy$allow_query <- FALSE
    expect_null(source_url_parts(catalog[[1]]$json, policy))
    expect_false(is.null(source_url_parts(sub("[?].*$", "", catalog[[1]]$json), policy)))
  }
})
