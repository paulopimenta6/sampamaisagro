test_that("1A contracts are deliberately validated and cannot silently widen", {
  c <- phase1_contract()
  expect_silent(validate_schema_contract(c))
  c$schema$properties$partners$items$properties$Fonte$types <- "anything"
  expect_error(validate_schema_contract(c), "types")
  c <- phase1_contract(); c$version <- NULL
  expect_error(validate_schema_contract(c), "version")
  c <- phase1_contract(); c$schema$additional_fields <- "accept_typo"
  expect_error(validate_schema_contract(c), "additional_fields")
  c <- phase1_contract(); c$schema$properties$partners$items$properties$Fonte$typo <- TRUE
  expect_error(validate_schema_contract(c), "schema")
})

test_that("1A validation differentiates structure, additions and insufficient evidence", {
  v02_forbid_http()
  good <- phase1_validate()
  expect_identical(good$decision, "allow")
  expect_identical(good$classification, "insufficient_evidence") # Email is all null.
  expect_identical(good$source_id, "demo.base")
  expect_identical(good$contract_id, "sampa.reports")
  expect_identical(phase1_validate("additive.json")$classification, "additive")
  expect_identical(phase1_validate("additive.json")$decision, "allow")
  for (file in c("missing-required.json", "type-drift.json", "nested-drift.json", "object-records.json")) {
    result <- phase1_validate(file)
    expect_identical(result$classification, "breaking")
    expect_identical(result$decision, "block")
    expect_gt(nrow(result$changes), 0)
  }
  expect_true(any(grepl("Subcategorias", phase1_validate("nested-drift.json")$changes$path)))
  expect_error(phase1_json("malformed.json"), "JSON")
  expect_identical(validate_source_payload(list(wrong = list()), phase1_contract())$decision, "block")
  duplicate <- jsonlite::parse_json('{"partners":[],"partners":[]}', simplifyVector = FALSE)
  expect_identical(validate_source_payload(duplicate, phase1_contract())$decision, "block")
  expect_false(grepl("Perfil sintético", jsonlite::toJSON(good, auto_unbox = TRUE), fixed = TRUE))
})

test_that("1A empty reports and absent coordinates do not imply removed fields", {
  empty <- phase1_validate("empty.json")
  expect_identical(empty$classification, "insufficient_evidence")
  expect_identical(empty$decision, "allow")
  expect_equal(empty$evidence$record_count, 0)
  expect_false(any(empty$changes$code == "required_field_missing"))
  x <- phase1_json(); x$partners <- lapply(x$partners, function(r) r[!names(r) %in% c("Latitudade", "Longitude")])
  expect_identical(validate_source_payload(x, phase1_contract())$decision, "allow")
  x <- phase1_json(); x$partners[[1]]$Latitudade <- "not a coordinate"
  expect_identical(validate_source_payload(x, phase1_contract())$classification, "suspicious")
})

test_that("1A fingerprint is canonical, structural, value and order independent", {
  parse <- function(x) jsonlite::parse_json(x, simplifyVector = FALSE)
  a <- parse('{"partners":[{"n":1,"tags":["a"],"at":"2000-01-01"},{"n":null,"tags":[],"at":"2001-01-01"}]}')
  b <- parse('{"partners":[{"at":"2099-02-01","tags":[],"n":null},{"tags":["other","values"],"n":1.5,"at":"2090-01-01"},{"n":null,"at":"2090","tags":[]}]}')
  fa <- schema_fingerprint(profile_source_schema(a))
  fb <- schema_fingerprint(profile_source_schema(b))
  expect_identical(fa$sha256, fb$sha256)
  expect_match(fa$sha256, "^[a-f0-9]{64}$")
  expect_identical(fa$canonical, fb$canonical)
  expect_false(grepl("2000|2099|other", fa$canonical))
  c <- parse('{"partners":[{"n":2,"tags":[{"label":"a"}],"at":"2090"}]}')
  expect_false(identical(fa$sha256, schema_fingerprint(profile_source_schema(c))$sha256))
  all_null <- schema_fingerprint(profile_source_schema(parse('{"x":null,"items":[]}')))
  expect_true(is.na(all_null$sha256))
  expect_identical(all_null$evidence_quality, "partial")
  expect_match(all_null$observed_sha256, "^[a-f0-9]{64}$")
  expect_setequal(all_null$unknown_paths, c("$/x", "$/items/*"))
})

test_that("1A optional removal is suspicious only with observable reference evidence", {
  before <- phase1_json(); after <- before
  after$partners <- lapply(after$partners, function(r) r[!names(r) %in% "Longitude"])
  ref <- profile_source_schema(before)
  out <- validate_source_payload(after, phase1_contract(), reference = ref)
  expect_identical(out$classification, "suspicious")
  expect_true("optional_field_disappeared" %in% out$changes$code)
  empty <- validate_source_payload(phase1_json("empty.json"), phase1_contract(), reference = ref)
  expect_identical(empty$classification, "insufficient_evidence")
  expect_false("optional_field_disappeared" %in% empty$changes$code)
})

test_that("1A nested object contracts and records paths are executable", {
  c <- phase1_contract()
  c$schema$properties$partners$items$properties$Detalhe <- list(types = "object", nullable = FALSE,
    additional_fields = "allow_and_report", properties = list(valor = list(types = "number", required = TRUE)))
  x <- phase1_json(); x$partners[[1]]$Detalhe <- list(valor = 1)
  expect_identical(validate_source_payload(x, c)$decision, "allow")
  x$partners[[1]]$Detalhe <- list(valor = list(1))
  expect_identical(validate_source_payload(x, c)$decision, "block")
  c$records_path <- "/missing"
  expect_error(validate_schema_contract(c), "records_path")
})

test_that("1A catalog and terms have separate contracts without external integrations", {
  c <- load_schema_contract("catalog-v1.yml")
  expect_identical(validate_source_payload(phase1_json("catalog.json"), c)$classification, "valid")
  expect_identical(validate_source_payload(list(), c)$decision, "block")
  c <- load_schema_contract("terms-v1.yml")
  text <- read_source_payload(phase1_path("terms.html"), "html")
  expect_identical(validate_source_payload(text, c, representation = "html")$classification, "valid")
  expect_identical(validate_source_payload("", c, representation = "html")$decision, "block")
})

test_that("1A P2-B required children count only observed object parents", {
  v02_forbid_http()
  contract <- list(contract_schema_version = 1L, contract_id = "synthetic.mixed", version = 1L,
    representations = "json", records_path = "", schema = list(types = "array", items = list(
      types = "object", additional_fields = "forbid", properties = list(Detalhe = list(
        types = c("object", "string"), nullable = TRUE, additional_fields = "forbid",
        properties = list(valor = list(types = "number", required = TRUE)))))))
  object <- list(valor = 1)
  empty_object <- jsonlite::parse_json("{}", simplifyVector = FALSE)
  cases <- list(
    object_and_string = list(values = list(object, "texto"), block = FALSE, missing = FALSE),
    missing_child_and_string = list(values = list(empty_object, "texto"), block = TRUE, missing = TRUE),
    strings_only = list(values = list("texto", "outro"), block = FALSE, missing = FALSE),
    two_objects_one_missing = list(values = list(object, empty_object), block = TRUE, missing = TRUE),
    object_and_null = list(values = list(object, NULL), block = FALSE, missing = FALSE),
    forbidden_type = list(values = list(object, TRUE), block = TRUE, missing = FALSE))
  for (name in names(cases)) {
    case <- cases[[name]]
    payload <- lapply(case$values, function(value) list(Detalhe = value))
    profile <- profile_source_schema(payload)
    # Both public-in-module entry points must agree, not only the instance walk.
    for (out in list(compare_schema_to_contract(profile, contract), validate_source_payload(payload, contract))) {
      expect_identical(out$classification, if (case$block) "breaking" else "valid", info = name)
      expect_identical(out$decision, if (case$block) "block" else "allow", info = name)
      missing <- out$changes$code == "required_field_missing" & out$changes$path == "$/*/Detalhe/valor"
      expect_identical(any(missing), case$missing, info = name)
      if (name == "forbidden_type") expect_true("incompatible_type" %in% out$changes$code)
    }
  }
  # Other permitted alternatives must not become object parents either.
  contract$schema$items$properties$Detalhe$types <- c("object", "string", "number", "boolean", "array")
  contract$schema$items$properties$Detalhe$items <- list(types = "number")
  payload <- lapply(list(object, "texto", 2, TRUE, list(3), NULL), function(value) list(Detalhe = value))
  out <- validate_source_payload(payload, contract)
  expect_identical(out$classification, "valid")
  expect_identical(out$decision, "allow")
  profile <- profile_source_schema(payload)
  detail <- Filter(function(n) n$path == "$/*/Detalhe", profile$nodes)[[1]]
  expect_identical(detail$object_observations, 1L)
  expect_identical(schema_fingerprint(profile), schema_fingerprint(profile_source_schema(
    c(payload, payload[c(1, 1, 2)]))))
  nulls <- validate_source_payload(list(list(Detalhe = NULL)), contract)
  expect_identical(nulls$classification, "insufficient_evidence")
  expect_identical(nulls$decision, "allow")
  expect_false("required_field_missing" %in% nulls$changes$code)
})

test_that("1A record pointers round-trip through canonical profile paths and reference drift", {
  v02_forbid_http()
  cases <- list(
    list(pointer = "", keys = character(), path = "$"),
    list(pointer = "/partners", keys = "partners", path = "$/partners"),
    list(pointer = "/items*", keys = "items*", path = "$/items~2"),
    list(pointer = "/items~1archived", keys = "items/archived", path = "$/items~1archived"),
    list(pointer = "/items~0archive", keys = "items~archive", path = "$/items~0archive"),
    list(pointer = "/~01", keys = "~1", path = "$/~01"),
    list(pointer = "/~02", keys = "~2", path = "$/~02"),
    list(pointer = "/wrapper~1*/items~0*", keys = c("wrapper/*", "items~*"), path = "$/wrapper~1~2/items~0~2"))
  records <- list(list(id = "one", note = "synthetic"), list(id = "two", note = "other"))
  wrap <- function(x, keys) {
    for (key in rev(keys)) x <- stats::setNames(list(x), key)
    x
  }
  for (case in cases) {
    schema <- list(types = "array", items = list(types = "object", additional_fields = "forbid",
      properties = list(id = list(types = "string", required = TRUE), note = list(types = "string"))))
    record_schema <- schema
    for (key in rev(case$keys)) schema <- list(types = "object", additional_fields = "forbid",
      properties = stats::setNames(list(schema), key))
    contract <- list(contract_schema_version = 1L, contract_id = "synthetic.pointer", version = 1L,
      representations = "json", records_path = case$pointer, schema = schema)
    payload <- wrap(records, case$keys)
    reference <- profile_source_schema(payload)
    expect_silent(validate_schema_contract(contract))
    expect_identical(source_records_schema(contract), record_schema)
    expect_identical(source_records(payload, contract), records)
    expect_identical(source_record_count(reference, contract), 2L, info = case$pointer)
    expect_true(paste0(case$path, "/*") %in% vapply(reference$nodes, `[[`, character(1), "path"))
    expect_identical(validate_source_payload(payload, contract)$classification, "valid")
    after <- wrap(lapply(records, function(row) row["id"]), case$keys)
    out <- compare_schema_to_contract(profile_source_schema(after), contract, reference = reference)
    expect_identical(out$evidence$record_count, 2L, info = case$pointer)
    expect_identical(out$classification, "suspicious", info = case$pointer)
    expect_identical(out$decision, "warn", info = case$pointer)
    expect_identical(out$changes$code, "optional_field_disappeared", info = case$pointer)
    expect_identical(out$changes$path, paste0(case$path, "/*/note"))
    expect_identical(validate_source_payload(after, contract, reference = reference)$decision, "warn")
    empty <- validate_source_payload(wrap(list(), case$keys), contract, reference = reference)
    expect_identical(empty$evidence$record_count, 0L)
    expect_identical(empty$classification, "insufficient_evidence")
    expect_false("optional_field_disappeared" %in% empty$changes$code)
  }
})

test_that("1A record lookup fixes preserve pre-review fixture fingerprints", {
  # Captured from the existing structural fingerprints before this correction.
  expected <- c(
    "report.json" = "015ad836c6adc40608921ea1d7d4b2b50df7cd450f8902a8fb10c3f128f7016e",
    "empty.json" = "2429af755156d808b18e97d1936f91cc12f52701c358508376668aff0a8bb073",
    "additive.json" = "56334715de23b01f345c224fffb8e1938830fb37cf9466e70e95cf833d14e0a8",
    "nested-drift.json" = "ff9c9cc3ecd801fe2a8cbe9da4d810a5fec2b03d552b8a1a2bae04f542b9c0ee")
  for (name in names(expected)) {
    fingerprint <- schema_fingerprint(profile_source_schema(phase1_json(name)))
    expect_identical(fingerprint$observed_sha256, expected[[name]], info = name)
    expect_identical(fingerprint$evidence_quality, "partial")
    expect_true(is.na(fingerprint$sha256))
  }
})
