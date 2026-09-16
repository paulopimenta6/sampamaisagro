library(targets)
pkgload::load_all(".", quiet = TRUE)
tar_option_set(packages = c("arrow", "dplyr", "sf"), format = "rds")

list(
  tar_target(config, read_sampa_config()),
  tar_target(collection_manifest, collect_sampa_data(config, include_terms = FALSE), cue = tar_cue(mode = "always")),
  tar_target(normalized, prepare_equipment_data(collection_manifest, config)),
  tar_target(validation, validate_equipment(normalized, config)),
  tar_target(processed_file, {
    file.path(config$data_dir, "processed", "equipment.parquet")
  }, format = "file")
)
