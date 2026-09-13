test_that("batch partitions and queue survive process boundaries", {
  temp <- withr::local_tempdir()
  cfg <- read_sampa_config(overrides = list(
    data_dir = file.path(temp, "data"), jobs_dir = file.path(temp, "jobs"), reports_dir = file.path(temp, "reports"),
    batch = list(chunk_size = 1, web_max_rows = 10, max_active_per_owner = 1)
  ))
  input <- data.frame(query_id = c("a", "b"), latitude = c(-23.55, -23.56),
    longitude = c(-46.63, -46.64), k = 2, radius_m = 5000)
  input_path <- file.path(temp, "origins.csv")
  readr::write_csv(input, input_path)
  direct <- process_batch(input_path, file.path(temp, "direct"), demo_equipment(), list(), cfg,
    list(k = 2, radius_m = 5000))
  expect_equal(length(list.files(direct$summary$partition_dir, pattern = "parquet$")), 2)

  job <- submit_batch_job(input_path, "owner", list(k = 2, radius_m = 5000), cfg)
  expect_match(job, "^job-")
  outcome <- run_worker_once(cfg, demo_equipment(), list())
  expect_false(inherits(outcome, "error"))
  expect_equal(sampamaisrural:::queue_list(cfg, "owner")$status[[1]], "completed")
})

test_that("batch preserves row errors across resume", {
  temp <- withr::local_tempdir()
  cfg <- read_sampa_config(overrides = list(
    data_dir = file.path(temp, "data"), jobs_dir = file.path(temp, "jobs"), reports_dir = file.path(temp, "reports"),
    batch = list(chunk_size = 1, web_max_rows = 10)
  ))
  input <- data.frame(query_id = c("good", "bad"), latitude = c(-23.55, 95), longitude = c(-46.63, -46.63))
  output <- file.path(temp, "resume")
  first <- process_batch(input, output, demo_equipment(), list(), cfg, list(k = 2, radius_m = 5000))
  second <- process_batch(input, output, demo_equipment(), list(), cfg, list(k = 2, radius_m = 5000), resume = TRUE)
  expect_equal(first$summary$error_rows, 1)
  expect_equal(second$summary$error_rows, 1)
  expect_equal(second$errors$query_id, "bad")
})

test_that("Shiny-style uploads preserve the original extension", {
  temp <- withr::local_tempdir()
  cfg <- read_sampa_config(overrides = list(
    data_dir = file.path(temp, "data"), jobs_dir = file.path(temp, "jobs"), reports_dir = file.path(temp, "reports")
  ))
  upload <- file.path(temp, "0")
  readr::write_csv(data.frame(query_id = "a", latitude = -23.55, longitude = -46.63), upload)
  job <- submit_batch_job(upload, "owner", list(k = 1, radius_m = 1000), cfg, original_name = "origens.csv")
  queued <- sampamaisrural:::queue_list(cfg, "owner")
  expect_equal(tools::file_ext(queued$input_path[queued$job_id == job]), "csv")
})
