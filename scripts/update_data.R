#!/usr/bin/env Rscript
root <- normalizePath(if (file.exists("DESCRIPTION")) "." else "..", mustWork = TRUE)
if (requireNamespace("sampamaisrural", quietly = TRUE)) {
  library(sampamaisrural)
} else {
  if (!requireNamespace("pkgload", quietly = TRUE)) stop("Instale o pacote ou pkgload.")
  pkgload::load_all(root, quiet = TRUE)
}

config <- read_sampa_config(file.path(root, "config.yml"))
message("Coletando catalogo e bases oficiais...")
manifest <- collect_sampa_data(config)
source_path <- sampamaisrural:::find_complete_snapshot(config)[1]
if (is.na(source_path) || !file.exists(source_path)) stop("A base completa nao foi encontrada no snapshot.")
message("Normalizando ", source_path)
normalized <- normalize_sampa_json(source_path)
checked <- validate_equipment(normalized, config)

processed <- file.path(config$data_dir, "processed")
dir.create(processed, recursive = TRUE, showWarnings = FALSE)
# Campos livres da fonte ficam somente no snapshot bruto de acesso controlado.
public_columns <- setdiff(names(checked$data), "source_payload")
arrow::write_parquet(checked$data[, public_columns, drop = FALSE],
  file.path(processed, "equipment.parquet"), compression = "zstd")
saveRDS(checked$data[, public_columns, drop = FALSE], file.path(processed, "equipment.rds"))
arrow::write_parquet(checked$quarantine[, public_columns, drop = FALSE],
  file.path(processed, "equipment_quarantine.parquet"), compression = "zstd")
readr::write_csv(checked$summary, file.path(processed, "data_quality_by_category.csv"))
readr::write_csv(checked$issues, file.path(processed, "data_quality_issues.csv"))
message("Concluido: ", nrow(checked$data), " registros; ", nrow(checked$eligible), " elegiveis.")
