test_that("1B I canonical JSON is ordered, typed, UTF-8 and round-trip stable", {
  a <- list(z = NULL, a = list(unicode = "ação 雪", values = list(TRUE, FALSE, 1L, 0.1, -0, NULL)))
  b <- list(a = list(values = list(TRUE, FALSE, 1, 0.1, 0, NULL), unicode = "ação 雪"), z = NULL)
  expect_identical(source_canonical_json(a), source_canonical_json(b))
  expect_identical(source_canonical_sha256(a), source_canonical_sha256(b))
  expect_match(source_canonical_sha256(a), "^[a-f0-9]{64}$")
  expect_identical(source_canonical_json(list(z = NULL, a = TRUE)), '{"a":true,"z":null}')
  expect_identical(source_canonical_json(list(FALSE, NULL)), '[false,null]')
  expect_identical(source_canonical_json(list()), "[]")
  expect_identical(source_canonical_json(stats::setNames(list(), character())), "{}")
  expect_identical(source_canonical_json(1L), source_canonical_json(1.0))
  changed <- a; changed$a$values[[3]] <- 2
  expect_false(identical(source_canonical_sha256(a), source_canonical_sha256(changed)))
  path <- withr::local_tempfile()
  source_write_json(a, path)
  expect_identical(source_canonical_sha256(a), source_canonical_sha256(source_read_json(path)))
  expect_identical(source_canonical_json(a), source_canonical_json(source_read_json(path)))
  latin <- iconv("ação", from = "UTF-8", to = "latin1"); Encoding(latin) <- "latin1"
  expect_identical(source_canonical_sha256(list(x = latin)), source_canonical_sha256(list(x = "ação")))
  expect_false(identical(source_canonical_sha256(list(x = TRUE)), source_canonical_sha256(list(x = "true"))))
  expect_false(identical(source_canonical_sha256(list(x = NULL)), source_canonical_sha256(list(x = "null"))))
  withr::local_options(OutDec = ",")
  expect_identical(source_canonical_json(a), source_canonical_json(b))
  expect_identical(source_canonical_json(1.25), "1.25")
  for (bad in list(NA_real_, NaN, Inf, as.raw(1), Sys.Date(), structure(list(a = 1), names = c("")), list(a = 1, a = 2))) {
    expect_error(source_canonical_json(bad), "canonical")
  }
  for (number in c(0.1, 1.2345678901234567, 1e-100, 1e100, .Machine$double.xmin, .Machine$double.xmax)) {
    parsed <- jsonlite::parse_json(source_canonical_json(number), simplifyVector = FALSE)
    expect_identical(source_canonical_json(number), source_canonical_json(parsed))
    expect_identical(as.numeric(number), as.numeric(parsed))
  }
})

test_that("1B I request identities isolate source, representation, URL and negotiation", {
  v02_forbid_http()
  a <- phase1_check_identity()
  expect_silent(validate_source_request_identity(a))
  expect_identical(a, phase1_check_identity())
  expect_identical(a$descriptor$representation_method, "GET")
  for (other in list(phase1_check_identity("csv"), phase1_check_identity(query = "?v=1"),
      phase1_check_identity(source_id = "demo.subset"), source_request_identity("demo.base", "json",
        "https://example.invalid/new/base-sintetica.json", phase1_registry()))) {
    expect_false(identical(a$sha256, other$sha256))
  }
  url <- a$descriptor$absolute_request_url
  for (headers in list(list(Accept = "application/json;profile=synthetic"), list(accept_encoding = "gzip"))) {
    expect_false(identical(a$sha256, source_request_identity("demo.base", "json", url, phase1_registry(), headers)$sha256))
  }
  one <- source_request_identity("demo.base", "json", paste0(url, "?a=1&b=2"), phase1_registry())
  two <- source_request_identity("demo.base", "json", paste0(url, "?b=2&a=1"), phase1_registry())
  expect_false(identical(one$sha256, two$sha256))
  for (ignored in list(list(`If-None-Match` = 'W/"synthetic"'), list(`If-Modified-Since` = "synthetic-date"),
      list(`User-Agent` = "sampamaisagro/0.3"), list(`User-Agent` = "sampamaisagro/9.9"))) {
    expect_identical(a, source_request_identity("demo.base", "json", url, phase1_registry(), ignored))
  }
  r <- phase1_registry(); r$registry_revision <- "synthetic-new"
  expect_identical(a, source_request_identity("demo.base", "json", url, r))
  expect_false(any(c("timestamp", "attempt", "force_content", "registry_revision", "contract_version", "user_agent") %in% names(a$descriptor)))
  expect_false(any(c("clock", "force_content", "contract_version", "registry_revision") %in% names(formals(source_request_identity))))
  headers <- list(Accept = "application/json", `Accept-Encoding` = "identity")
  expect_identical(a, source_request_identity("demo.base", "json", url, r, rev(headers)))
  reordered <- a; reordered$descriptor <- rev(reordered$descriptor)
  expect_silent(validate_source_request_identity(reordered))
  expect_identical(a$sha256, source_canonical_sha256(reordered$descriptor))
  bad <- a; bad$descriptor$request_headers$accept <- "text/html"
  expect_error(validate_source_request_identity(bad), "checksum")
  expect_error(source_request_identity("demo.base", "json", url, r, list(Cookie = "forbidden")), "header")
  expect_error(source_request_identity("demo.base", "json", url, r, list(Accept = NA_character_)), "header")
  expect_error(source_request_identity("demo.base", "json", url, r, list(Accept = NULL)), "header")
  unicode <- source_request_identity("demo.base", "json", paste0(url, "?label=ação"), r)
  expect_identical(unicode$sha256, source_canonical_sha256(jsonlite::parse_json(unicode$canonical, simplifyVector = FALSE)))
})

test_that("1B I identity reuses the original 1A URL, slug and representation policy", {
  v02_forbid_http()
  bad <- c("https://example.invalid/x/../base-sintetica.json", "https://example.invalid/./base-sintetica.json",
    "https://example.invalid/x/%2e%2e/base-sintetica.json", "http://example.invalid/base-sintetica.json",
    "https://user:secret@example.invalid/base-sintetica.json", "https://other.invalid/base-sintetica.json",
    "https://example.invalid:8443/base-sintetica.json", "https://example.invalid/base-sintetica.json#fragment",
    "https://example.invalid/other.json", "https://example.invalid/base-sintetica.csv")
  for (url in bad) expect_error(source_request_identity("demo.base", "json", url, phase1_registry()), "URL")
  expect_error(source_request_identity("unknown", "json", "https://example.invalid/base.json", phase1_registry()), "source")
  expect_error(source_request_identity("demo.base", "html", "https://example.invalid/base.html", phase1_registry()), "representation")
  expect_silent(source_request_identity("demo.base", "json", "https://example.invalid/legitimate/path/base-sintetica.json?x=1", phase1_registry()))
})
