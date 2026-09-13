library(targets)
pkgload::load_all(".", quiet = TRUE)
tar_option_set(packages = c("arrow", "dplyr", "sf"), format = "rds")

list(
  tar_target(config, read_sampa_config()),
  tar_target(collection_manifest, collect_sampa_data(config), cue = tar_cue(mode = "always")),
  tar_target(raw_complete, sampamaisrural:::find_complete_snapshot(config)[1]),
  tar_target(normalized, normalize_sampa_json(raw_complete)),
  tar_target(validation, validate_equipment(normalized, config)),
  tar_target(processed_file, {
    path <- file.path(config$data_dir, "processed", "equipment.parquet")
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    arrow::write_parquet(validation$data[, setdiff(names(validation$data), "source_payload"), drop = FALSE], path)
    path
  }, format = "file")
)
