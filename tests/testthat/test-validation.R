test_that("invalid and outside coordinates are quarantined", {
  eq <- demo_equipment()[1:4, ]
  eq$latitude <- c(-23.5, NA, 95, -22)
  checked <- validate_equipment(eq)
  expect_equal(nrow(checked$eligible), 1)
  expect_equal(nrow(checked$quarantine), 3)
  expect_setequal(checked$quarantine$coordinate_status,
    c("incomplete_coordinate", "invalid_coordinate", "outside_study_area"))
})

quality_fixture <- function() {
  data.frame(
    equipment_id = c(sprintf("profile-%02d", 1:6), "profile-01", sprintf("profile-%02d", 8:12)),
    record_version_id = c("v1", "v2", "v3", "v4", "v5", "v1", "v7", "v8", "v1", "v10", "v11", "v12"),
    equipment_name = c("Horta", NA, "", "   ", "Produtor", "Copia", "Mercado", "", "   ", NA, "Perfil A", "Perfil B"),
    category = c(rep("Agricultura", 6), rep("Mercados", 3), NA, "", "   "),
    postal_code = c("01001000", NA, "", "   ", "01001000", "01001000", "01001000", "", "   ", NA, "01001000", "01001000"),
    latitude = c(-23.5, NA, NA, 95, -22, rep(-23.5, 7)),
    longitude = c(-46.6, NA, rep(-46.6, 10)),
    stringsAsFactors = FALSE
  )
}

quality_config <- function() {
  list(data_dir = tempdir(), spatial = list(
    bbox = list(xmin = -47.1, ymin = -24.1, xmax = -46.2, ymax = -23.3)))
}

quality_columns <- function() {
  c("category", "n", "coordinate_n", "coordinate_pct", "cep_n",
    "missing_coordinate_n", "missing_coordinate_pct",
    "incomplete_coordinate_n", "incomplete_coordinate_pct",
    "invalid_coordinate_n", "invalid_coordinate_pct",
    "outside_study_area_n", "outside_study_area_pct",
    "spatial_eligible_n", "spatial_eligible_pct",
    "missing_name_n", "missing_name_pct",
    "missing_category_n", "missing_category_pct",
    "missing_cep_n", "missing_cep_pct")
}

test_that("quality counts and percentages use all supplied profiles in each category", {
  checked <- validate_equipment(quality_fixture(), quality_config())
  summary <- data_quality_summary(checked$data)
  expected <- data.frame(
    category = c("Agricultura", "Mercados", "Sem categoria"),
    n = c(6L, 3L, 3L), coordinate_n = c(2L, 3L, 3L), cep_n = c(3L, 1L, 2L),
    missing_coordinate_n = c(1L, 0L, 0L), incomplete_coordinate_n = c(1L, 0L, 0L),
    invalid_coordinate_n = c(1L, 0L, 0L), outside_study_area_n = c(1L, 0L, 0L),
    spatial_eligible_n = c(1L, 2L, 3L), missing_name_n = c(3L, 2L, 1L),
    missing_category_n = c(0L, 0L, 3L), missing_cep_n = c(3L, 2L, 1L),
    stringsAsFactors = FALSE
  )

  expect_identical(names(summary), quality_columns())
  expect_equal(summary[, names(expected)], expected)
  expect_equal(summary, checked$summary)
  expect_true(grepl("missing_category", checked$data$quality_flags[12], fixed = TRUE))
  expect_true(all(grepl("missing_name", checked$data$quality_flags[c(4, 9)], fixed = TRUE)))
  missing_category_issues <- checked$issues$n[checked$issues$issue == "missing_category"]
  expect_equal(missing_category_issues, 3L)
  expect_equal(missing_category_issues, sum(summary$missing_category_n))
  expect_equal(sum(grepl("missing_name", checked$data$quality_flags, fixed = TRUE)),
    sum(summary$missing_name_n))
  expect_equal(sum(summary$n), 12L)
  expect_equal(summary$cep_n + summary$missing_cep_n, summary$n)
  count_columns <- c("coordinate_n", "missing_coordinate_n", "incomplete_coordinate_n",
    "invalid_coordinate_n", "outside_study_area_n")
  expect_equal(unname(rowSums(summary[, count_columns])), as.numeric(summary$n))
  for (count_col in setdiff(names(expected), c("category", "n", "cep_n"))) {
    pct_col <- sub("_n$", "_pct", count_col)
    expect_equal(summary[[pct_col]], 100 * expected[[count_col]] / expected$n, label = pct_col)
  }
})

test_that("spatial eligibility preserves version precedence and global duplicate exclusion", {
  equipment <- quality_fixture()
  checked <- validate_equipment(equipment, quality_config())
  expect_identical(which(grepl("duplicate_record", checked$data$quality_flags)), c(6L, 9L))
  expect_identical(checked$eligible$record_version_id, c("v1", "v7", "v8", "v10", "v11", "v12"))
  expect_equal(sum(checked$summary$spatial_eligible_n), nrow(checked$eligible))
  # The repeated equipment_id is eligible because its record version differs.
  expect_equal(sum(checked$eligible$equipment_id == "profile-01"), 2L)
  expect_equal(checked$summary$coordinate_n, c(2L, 3L, 3L))

  equipment$record_version_id <- NULL
  fallback <- validate_equipment(equipment, quality_config())
  expect_identical(which(grepl("duplicate_record", fallback$data$quality_flags)), 7L)
  expect_equal(fallback$summary$spatial_eligible_n, c(2L, 2L, 3L))
  expect_equal(sum(fallback$summary$spatial_eligible_n), nrow(fallback$eligible))
})

test_that("derived geocodes retain the existing coordinate eligibility semantics", {
  annotated <- validate_equipment(quality_fixture(), quality_config())$data
  annotated$coordinate_status[1] <- "derived_geocode"
  summary <- data_quality_summary(annotated)
  expect_equal(summary$coordinate_n, c(2L, 3L, 3L))
  expect_equal(summary$spatial_eligible_n, c(1L, 2L, 3L))
})

test_that("an absent optional postal code column counts as missing", {
  equipment <- quality_fixture()
  equipment$postal_code <- NULL
  summary <- validate_equipment(equipment, quality_config())$summary
  expect_equal(summary$cep_n, c(0L, 0L, 0L))
  expect_equal(summary$missing_cep_n, summary$n)
  expect_equal(summary$missing_cep_pct, c(100, 100, 100))
})

test_that("empty quality summaries preserve the complete typed schema", {
  equipment <- quality_fixture()[0, ]
  checked <- validate_equipment(equipment, quality_config())
  summary <- data_quality_summary(checked$data)
  expect_identical(names(summary), quality_columns())
  expect_identical(nrow(summary), 0L)
  expect_identical(summary$category, character())
  for (column in setdiff(quality_columns(), "category")) {
    expect_identical(summary[[column]], if (grepl("_pct$", column)) numeric() else integer(), label = column)
  }
  expect_identical(summary, checked$summary)
  expect_equal(nrow(checked$eligible), 0L)
  expect_equal(nrow(checked$quarantine), 0L)
})
