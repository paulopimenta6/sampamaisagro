test_that("1A pairs are consistent according to the declared lossy projection", {
  v02_forbid_http()
  result <- validate_source_pair(phase1_json(), phase1_path("report.csv"), phase1_contract(), "demo.base")
  expect_identical(result$classification, "consistent_under_projection")
  expect_identical(result$decision, "allow")
  expect_equal(result$json_records, 3)
  expect_equal(result$csv_records, 3)
  expect_true(result$projection_lossy)
  expect_false(grepl("Perfil sintético", jsonlite::toJSON(result, auto_unbox = TRUE), fixed = TRUE))
  x <- phase1_json(); x$partners <- rev(x$partners)
  expect_identical(validate_source_pair(x, phase1_path("report.csv"), phase1_contract())$classification,
    "consistent_under_projection")
  empty <- validate_source_pair(phase1_json("empty.json"), phase1_path("empty.csv"), phase1_contract())
  expect_identical(empty$classification, "consistent_under_projection")
})

test_that("1A pair checks detect content differences and retain duplicate multiplicity", {
  result <- validate_source_pair(phase1_json(), phase1_path("same-count-different.csv"), phase1_contract())
  expect_equal(result$json_records, result$csv_records)
  expect_identical(result$classification, "inconsistent_under_projection")
  expect_identical(result$decision, "block")
  x <- phase1_json(); x$partners <- x$partners[c(1, 2, 2)]
  expect_identical(validate_source_pair(x, phase1_path("report.csv"), phase1_contract())$decision, "block")
})

test_that("1A CSV parsing keeps quoting, BOM and numeric representations", {
  csv <- read_source_payload(phase1_path("report.csv"), "csv")
  expect_identical(names(csv)[1], "Nome do Perfil")
  expect_match(csv[["Endereço comercial"]][1], "\n", fixed = TRUE)
  expect_identical(csv$Subcategorias[1], "item com, vírgula, segundo item")
  csv$Longitude[1] <- "2e0"
  csv$Latitudade[1] <- "1.50000"
  expect_identical(validate_source_pair(phase1_json(), csv, phase1_contract())$decision, "allow")
  csv$Longitude[1] <- "2.000001"
  expect_identical(validate_source_pair(phase1_json(), csv, phase1_contract())$decision, "block")
  malformed <- withr::local_tempfile(fileext = ".csv")
  writeLines(c('a;b', '1;2;3'), malformed)
  expect_error(read_source_payload(malformed, "csv"), "CSV")
  expect_identical(validate_source_pair(phase1_json("nested-drift.json"),
    phase1_path("report.csv"), phase1_contract())$decision, "block")
})

test_that("1A numeric projection retains precision and cannot collide with literal strings", {
  x <- phase1_json(); csv <- read_source_payload(phase1_path("report.csv"), "csv")
  x$partners[[1]]$Longitude <- 1.2345678901234567
  csv$Longitude[1] <- "1.2345678901234567"
  expect_identical(validate_source_pair(x, csv, phase1_contract())$decision, "allow")
  x$partners[[1]]$Longitude <- "number:0x1p+1"
  csv$Longitude[1] <- "2"
  expect_identical(validate_source_pair(x, csv, phase1_contract())$decision, "block")
})

test_that("1A pair comparison does not claim unsupported nested projections", {
  x <- phase1_json(); csv <- read_source_payload(phase1_path("report.csv"), "csv")
  x$partners <- lapply(x$partners, function(r) {r$Extra <- list(nested = 1); r})
  csv$Extra <- "unknown serialization"
  out <- validate_source_pair(x, csv, phase1_contract())
  expect_identical(out$classification, "insufficient_evidence")
  expect_identical(out$decision, "warn")
})

for (case in c("equal_with_unsupported", "different_with_unsupported", "equal_supported_only", "different_supported_only")) {
  test_that(paste("1A P2-A comparable evidence has precedence:", case), {
    v02_forbid_http()
    x <- phase1_json(); csv <- read_source_payload(phase1_path("report.csv"), "csv")
    unsupported <- grepl("with_unsupported", case, fixed = TRUE)
    different <- startsWith(case, "different")
    if (unsupported) {
      # Keep the nested field in both inputs, including the mismatch cases.
      x$partners[[1]]$Extra <- list(nested = 1)
      x$partners[[2]]$Extra <- "projectable in this row only"
      x$partners[[3]]$Extra <- list(nested = 1)
      csv$Extra <- "unknown serialization"
    }
    if (different) csv[["Nome do Perfil"]][1] <- "Outro perfil sintético"
    out <- validate_source_pair(x, csv, phase1_contract())
    expect_identical(out$classification, if (different) "inconsistent_under_projection" else
      if (unsupported) "insufficient_evidence" else "consistent_under_projection")
    expect_identical(out$decision, if (different) "block" else if (unsupported) "warn" else "allow")
    expect_setequal(out$compared_fields, setdiff(names(csv), "Extra"))
    expect_identical(out$unsupported_fields, if (unsupported) "Extra" else character())
    expect_identical(out$divergent_fields, if (different) "Nome do Perfil" else character())
    expect_identical(out$row_multiset_matches, !different)
    expect_identical(out$comparison_coverage, list(total_fields = ncol(csv),
      compared_fields = ncol(csv) - as.integer(unsupported), unsupported_fields = as.integer(unsupported)))
    expect_identical("unsupported_projection_shape" %in% out$issues, unsupported)
    expect_identical("different_projected_row_multisets" %in% out$issues, different)
    expect_false(grepl("Outro perfil sintético|unknown serialization", jsonlite::toJSON(out, auto_unbox = TRUE)))
  })
}

test_that("1A P2-A partial comparison preserves duplicates and row associations", {
  v02_forbid_http()
  x <- phase1_json(); csv <- read_source_payload(phase1_path("report.csv"), "csv")
  x$partners <- lapply(x$partners, function(r) {r$Extra <- list(nested = 1); r})
  csv$Extra <- "unknown serialization"
  x$partners <- x$partners[c(3, 2, 1)]
  expect_identical(validate_source_pair(x, csv, phase1_contract())$decision, "warn")
  duplicated <- x; duplicated$partners <- duplicated$partners[c(1, 2, 2)]
  out <- validate_source_pair(duplicated, csv, phase1_contract())
  expect_identical(out$decision, "block")
  expect_true("Nome do Perfil" %in% out$divergent_fields)
  # Individual column multisets still agree; their row associations do not.
  csv[["Nome do Perfil"]][1:2] <- rev(csv[["Nome do Perfil"]][1:2])
  out <- validate_source_pair(x, csv, phase1_contract())
  expect_identical(out$decision, "block")
  expect_identical(out$divergent_fields, character())
  expect_false(out$row_multiset_matches)
  expect_true("different_projected_row_associations" %in% out$issues)
  expect_identical(out$unsupported_fields, "Extra")
})
