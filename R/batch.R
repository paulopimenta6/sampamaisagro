read_origin_file <- function(path) {
  if (!file.exists(path)) stop("Arquivo de origens nao encontrado: ", path)
  extension <- tolower(tools::file_ext(path))
  data <- switch(extension,
    csv = readr::read_csv(path, show_col_types = FALSE, progress = FALSE),
    tsv = readr::read_tsv(path, show_col_types = FALSE, progress = FALSE),
    txt = readr::read_delim(path, delim = NULL, show_col_types = FALSE, progress = FALSE),
    xlsx = readxl::read_excel(path),
    xls = readxl::read_excel(path),
    parquet = arrow::read_parquet(path),
    stop("Formato nao suportado: ", extension)
  )
  as.data.frame(data, stringsAsFactors = FALSE)
}

batch_manifest <- function(input_path, origins, parameters, data_snapshot, network_snapshot) {
  list(
    schema_version = "1.0.0",
    created_at = utc_now(),
    input_file = basename(input_path %||% "in_memory"),
    input_sha256 = if (!is.null(input_path) && file.exists(input_path)) sha256_file(input_path) else
      digest::digest(origins, algo = "sha256"),
    row_count = nrow(origins),
    parameters = parameters,
    data_snapshot = data_snapshot,
    network_snapshot = network_snapshot,
    r_version = R.version.string,
    package_version = tryCatch(as.character(utils::packageVersion("sampamaisrural")), error = function(e) "source")
  )
}

write_batch_partition <- function(results, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(results, path, compression = "zstd")
  invisible(path)
}

#' Process a large origin file with checkpoints
#'
#' @param input File path or data frame containing `query_id` and CEP or coordinates.
#' @param output_dir Job-specific output directory.
#' @param equipment Canonical equipment data.
#' @param graphs Named routing graphs.
#' @param config Project configuration.
#' @param parameters Query parameters passed to `calculate_proximity()`.
#' @param resume Resume from completed chunk checkpoints.
#' @param progress_callback Optional function `(completed, total, message)`.
#' @return Job summary containing paths, validation errors and manifest.
#' @export
process_batch <- function(input, output_dir, equipment = load_equipment_data(), graphs = list(),
                          config = read_sampa_config(), parameters = list(), resume = TRUE,
                          progress_callback = NULL) {
  input_path <- if (is.character(input) && length(input) == 1L) input else NULL
  origins <- if (is.null(input_path)) as.data.frame(input, stringsAsFactors = FALSE) else read_origin_file(input_path)
  if (nrow(origins) > config$batch$web_max_rows) {
    stop("O lote excede o limite configurado de ", config$batch$web_max_rows, " linhas.")
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  partition_dir <- file.path(output_dir, "partitions")
  error_dir <- file.path(output_dir, "errors")
  dir.create(partition_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(error_dir, recursive = TRUE, showWarnings = FALSE)
  checkpoint_path <- file.path(output_dir, "checkpoint.rds")
  chunk_size <- as.integer(config$batch$chunk_size)
  chunk_id <- ceiling(seq_len(nrow(origins)) / chunk_size)
  total_chunks <- if (nrow(origins)) max(chunk_id) else 0L
  completed <- integer()
  if (isTRUE(resume) && file.exists(checkpoint_path)) completed <- readRDS(checkpoint_path)$completed %||% integer()

  manifest <- batch_manifest(
    input_path, origins, parameters,
    unique(equipment$snapshot_date %||% NA_character_), config$network$snapshot %||% NA_character_
  )
  atomic_write_json(manifest, file.path(output_dir, "manifest.json"))
  for (chunk in seq_len(total_chunks)) {
    if (chunk %in% completed &&
        file.exists(file.path(partition_dir, sprintf("part-%05d.parquet", chunk))) &&
        file.exists(file.path(error_dir, sprintf("errors-%05d.csv", chunk)))) next
    rows <- which(chunk_id == chunk)
    current <- origins[rows, , drop = FALSE]
    current$.input_row <- rows
    resolved <- resolve_origins(current, config)
    mapped <- resolved$errors
    if (nrow(mapped)) {
      mapped$input_row <- rows[pmin(mapped$row, length(rows))]
    } else {
      mapped$input_row <- integer()
    }
    readr::write_csv(mapped, file.path(error_dir, sprintf("errors-%05d.csv", chunk)), na = "")
    if (nrow(resolved$valid)) {
      args <- c(list(origins = resolved$valid, equipment = equipment, graphs = graphs, config = config), parameters)
      result <- do.call(calculate_proximity, args)
    } else {
      result <- data.frame()
    }
    write_batch_partition(result, file.path(partition_dir, sprintf("part-%05d.parquet", chunk)))
    completed <- sort(unique(c(completed, chunk)))
    atomic_save_rds(list(completed = completed, total = total_chunks, updated_at = utc_now()), checkpoint_path)
    if (is.function(progress_callback)) progress_callback(length(completed), total_chunks,
      sprintf("Bloco %d de %d concluido", chunk, total_chunks))
  }

  error_parts <- list.files(error_dir, pattern = "\\.csv$", full.names = TRUE)
  errors <- dplyr::bind_rows(lapply(error_parts, function(path) readr::read_csv(
    path, show_col_types = FALSE, progress = FALSE, col_types = readr::cols(.default = readr::col_character())
  )))
  if (nrow(errors)) {
    errors$row <- as.integer(errors$row)
    errors$input_row <- as.integer(errors$input_row)
  }
  error_path <- file.path(output_dir, "validation_errors.csv")
  readr::write_csv(errors, error_path, na = "")
  error_input_rows <- if ("input_row" %in% names(errors)) errors$input_row else integer()
  summary <- list(
    status = "completed", completed_at = utc_now(), total_rows = nrow(origins),
    valid_rows = nrow(origins) - length(unique(error_input_rows)),
    error_rows = length(unique(error_input_rows)),
    partition_dir = normalizePath(partition_dir, mustWork = FALSE), error_file = error_path
  )
  atomic_write_json(summary, file.path(output_dir, "summary.json"))
  list(manifest = manifest, summary = summary, errors = errors, output_dir = output_dir)
}
