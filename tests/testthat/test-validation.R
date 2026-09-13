test_that("invalid and outside coordinates are quarantined", {
  eq <- demo_equipment()[1:4, ]
  eq$latitude <- c(-23.5, NA, 95, -22)
  checked <- validate_equipment(eq)
  expect_equal(nrow(checked$eligible), 1)
  expect_equal(nrow(checked$quarantine), 3)
  expect_setequal(checked$quarantine$coordinate_status,
    c("incomplete_coordinate", "invalid_coordinate", "outside_study_area"))
})
