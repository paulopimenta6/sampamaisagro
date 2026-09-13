queue_path <- function(config) file.path(config$jobs_dir, "jobs.sqlite")

queue_connect <- function(config) {
  ensure_project_dirs(config)
  con <- DBI::dbConnect(RSQLite::SQLite(), queue_path(config))
  DBI::dbExecute(con, "PRAGMA busy_timeout=5000")
  con
}

#' Initialize the durable batch job queue
#'
#' @param config Project configuration.
#' @return Queue database path, invisibly.
#' @export
init_job_queue <- function(config = read_sampa_config()) {
  con <- queue_connect(config)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, paste(
    "CREATE TABLE IF NOT EXISTS jobs (",
    "job_id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, status TEXT NOT NULL,",
    "created_at TEXT NOT NULL, started_at TEXT, completed_at TEXT, heartbeat_at TEXT,",
    "input_path TEXT NOT NULL, output_dir TEXT NOT NULL, parameters_json TEXT NOT NULL,",
    "progress_done INTEGER NOT NULL DEFAULT 0, progress_total INTEGER NOT NULL DEFAULT 0,",
    "message TEXT, error_message TEXT)"
  ))
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS jobs_status_created ON jobs(status, created_at)")
  DBI::dbExecute(con, "PRAGMA journal_mode=WAL")
  invisible(queue_path(config))
}

queue_list <- function(config = read_sampa_config(), owner_id = NULL) {
  init_job_queue(config)
  con <- queue_connect(config)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  if (is.null(owner_id)) {
    DBI::dbGetQuery(con, "SELECT * FROM jobs ORDER BY created_at DESC")
  } else {
    DBI::dbGetQuery(con, "SELECT * FROM jobs WHERE owner_id = ? ORDER BY created_at DESC", params = list(owner_id))
  }
}

new_job_id <- function() paste0("job-", substr(digest::digest(paste(utc_now(), stats::runif(1))), 1L, 16L))

#' Submit an origin file to the durable batch queue
#'
#' @param input_file CSV, spreadsheet or Parquet origin file.
#' @param owner_id Opaque session or researcher identifier.
#' @param parameters Query parameters.
#' @param config Project configuration.
#' @param original_name Original upload name, used to preserve the file extension.
#' @return Submitted job id.
#' @export
submit_batch_job <- function(input_file, owner_id = "local", parameters = list(),
                             config = read_sampa_config(), original_name = NULL) {
  if (!file.exists(input_file)) stop("Arquivo de entrada inexistente.")
  init_job_queue(config)
  con <- queue_connect(config)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  active <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM jobs WHERE owner_id = ? AND status IN ('queued','running')",
    params = list(owner_id))$n[[1]]
  if (active >= config$batch$max_active_per_owner) stop("Ja existe um lote ativo para este usuario.")
  job_id <- new_job_id()
  output_dir <- file.path(config$jobs_dir, job_id)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  extension_source <- original_name %||% input_file
  extension <- tolower(tools::file_ext(extension_source))
  if (!extension %in% c("csv", "tsv", "txt", "xlsx", "xls", "parquet")) {
    stop("Extensao de lote nao suportada: ", extension)
  }
  stored_input <- file.path(output_dir, paste0("input.", extension))
  if (!file.copy(input_file, stored_input, overwrite = FALSE)) stop("Nao foi possivel copiar o arquivo do lote.")
  DBI::dbExecute(con, paste(
    "INSERT INTO jobs(job_id, owner_id, status, created_at, input_path, output_dir, parameters_json)",
    "VALUES (?, ?, 'queued', ?, ?, ?, ?)"
  ), params = list(job_id, owner_id, utc_now(), stored_input, output_dir,
    jsonlite::toJSON(parameters, auto_unbox = TRUE, null = "null")))
  job_id
}

claim_next_job <- function(config = read_sampa_config()) {
  con <- queue_connect(config)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbWithTransaction(con, {
    candidate <- DBI::dbGetQuery(con,
      "SELECT job_id FROM jobs WHERE status = 'queued' ORDER BY created_at LIMIT 1")
    if (!nrow(candidate)) return(NULL)
    job_id <- candidate$job_id[[1]]
    now <- utc_now()
    changed <- DBI::dbExecute(con, paste(
      "UPDATE jobs SET status='running', started_at=?, heartbeat_at=?, message='Preparando lote'",
      "WHERE job_id=? AND status='queued'"
    ), params = list(now, now, job_id))
    if (changed != 1L) return(NULL)
    DBI::dbGetQuery(con, "SELECT * FROM jobs WHERE job_id=?", params = list(job_id))[1, , drop = FALSE]
  })
}

requeue_stale_jobs <- function(config = read_sampa_config(), stale_minutes = 30) {
  con <- queue_connect(config)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  cutoff <- format(Sys.time() - as.difftime(stale_minutes, units = "mins"), tz = "UTC", usetz = TRUE)
  DBI::dbExecute(con, paste(
    "UPDATE jobs SET status='queued', started_at=NULL, message='Retomando apos heartbeat expirado'",
    "WHERE status='running' AND heartbeat_at < ?"
  ), params = list(cutoff))
}

update_job <- function(job_id, config, status = NULL, done = NULL, total = NULL,
                       message = NULL, error_message = NULL) {
  con <- queue_connect(config)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  fields <- c(heartbeat_at = utc_now())
  if (!is.null(status)) fields <- c(fields, status = status)
  if (!is.null(done)) fields <- c(fields, progress_done = as.character(done))
  if (!is.null(total)) fields <- c(fields, progress_total = as.character(total))
  if (!is.null(message)) fields <- c(fields, message = message)
  if (!is.null(error_message)) fields <- c(fields, error_message = error_message)
  if (identical(status, "completed") || identical(status, "failed")) fields <- c(fields, completed_at = utc_now())
  sql <- paste0("UPDATE jobs SET ", paste(paste0(names(fields), "=?"), collapse = ", "), " WHERE job_id=?")
  DBI::dbExecute(con, sql, params = c(as.list(unname(fields)), list(job_id)))
  invisible(job_id)
}

#' Run at most one queued batch job
#'
#' @param config Project configuration.
#' @param equipment Optional already-loaded equipment data.
#' @param graphs Optional already-loaded graphs.
#' @return `NULL` if no job exists, otherwise job outcome.
#' @export
run_worker_once <- function(config = read_sampa_config(), equipment = NULL, graphs = NULL) {
  init_job_queue(config)
  requeue_stale_jobs(config)
  job <- claim_next_job(config)
  if (is.null(job)) return(NULL)
  equipment <- equipment %||% load_equipment_data(config)
  graphs <- graphs %||% load_network_graphs(config)
  parameters <- jsonlite::fromJSON(job$parameters_json[[1]], simplifyVector = TRUE)
  callback <- function(done, total, message) update_job(job$job_id[[1]], config,
    done = done, total = total, message = message)
  outcome <- tryCatch(
    process_batch(job$input_path[[1]], job$output_dir[[1]], equipment, graphs, config,
      parameters, resume = TRUE, progress_callback = callback),
    error = identity
  )
  if (inherits(outcome, "error")) {
    update_job(job$job_id[[1]], config, status = "failed", message = "Falha no processamento",
      error_message = conditionMessage(outcome))
  } else {
    update_job(job$job_id[[1]], config, status = "completed", message = "Lote concluido")
  }
  outcome
}

cleanup_expired_jobs <- function(config = read_sampa_config()) {
  jobs <- queue_list(config)
  if (!nrow(jobs)) return(invisible(integer()))
  completed <- as.POSIXct(jobs$completed_at, tz = "UTC")
  cutoff <- Sys.time() - as.difftime(config$batch$retention_days, units = "days")
  expired <- which(jobs$status %in% c("completed", "failed") & !is.na(completed) & completed < cutoff)
  # Deliberately retain the SQLite audit row; only generated artifacts expire.
  for (i in expired) {
    files <- list.files(jobs$output_dir[i], full.names = TRUE, recursive = TRUE, include.dirs = FALSE)
    if (length(files)) unlink(files)
    dirs <- list.dirs(jobs$output_dir[i], full.names = TRUE, recursive = TRUE)
    dirs <- dirs[order(nchar(dirs), decreasing = TRUE)]
    for (dir in dirs) unlink(dir, recursive = FALSE)
  }
  invisible(expired)
}
