# The browser never loads a routing graph. One supervised R child per app does
# the work; immutable result partitions and an atomic manifest carry progress.
web_terminal <- function(status) status %in% c("completed", "failed", "cancelled")

web_job_read <- function(job_dir) readRDS(file.path(job_dir, "progress.rds"))

web_job_write <- function(state, job_dir) {
  state$updated_at <- as.numeric(Sys.time())
  atomic_save_rds(state, file.path(job_dir, "progress.rds"))
  state
}

web_job_results <- function(job_dir, state = web_job_read(job_dir)) {
  parts <- lapply(file.path(job_dir, state$parts), readRDS)
  diagnostics <- dplyr::bind_rows(lapply(parts, attr, which = "routing_diagnostics"))
  result <- dplyr::bind_rows(parts)
  attr(result, "routing_diagnostics") <- diagnostics
  attr(result, "analysis") <- state[c("job_id", "status", "requested_modes", "directions",
    "completed_units", "total_units", "stage")]
  result
}

web_export_results <- function(result, state) {
  result$analysis_status <- rep(state$status, nrow(result))
  result$analysis_job_id <- rep(state$job_id, nrow(result))
  result$requested_modes <- rep(paste(state$requested_modes, collapse = ","), nrow(result))
  result$completed_units <- rep(state$completed_units, nrow(result))
  result$total_units <- rep(state$total_units, nrow(result))
  result
}

web_job_worker <- function(request_path) {
  request <- readRDS(request_path)
  job_dir <- dirname(request_path)
  state <- web_job_read(job_dir)
  publish <- function(stage, status = "running") {
    state$stage <<- stage
    state$status <<- status
    state <<- web_job_write(state, job_dir)
  }
  append_part <- function(result) {
    name <- sprintf("part-%05d.rds", length(state$parts) + 1L)
    atomic_save_rds(result, file.path(job_dir, name))
    state$parts <<- c(state$parts, name)
    state$completed_units <<- state$completed_units + 1L
    publish(state$stage)
  }
  tryCatch({
    publish("Validando as origens no banco local")
    config <- request$config
    # Interactive queries must never fall back to an online geocoder.
    config$geocoding$offline <- TRUE
    input <- if (is.character(request$input)) read_origin_file(request$input) else request$input
    if (!nrow(input)) stop("O arquivo n\u00e3o cont\u00e9m origens.")
    if (nrow(input) > 100L) stop("Na interface, envie at\u00e9 100 origens. Use scripts/batch.R para lotes maiores.")
    resolved <- resolve_origins(input, config)
    state$errors <- resolved$errors
    state$origins <- resolved$valid
    names(state$origins)[names(state$origins) == "query_id"] <- "origin_id"
    n <- nrow(state$origins)
    state$total_units <- n * (1L + length(request$modes))
    publish("Origens verificadas")
    if (!n) stop(paste(unique(resolved$errors$message), collapse = "; "))
    for (i in seq_len(n)) {
      publish(sprintf("Dist\u00e2ncias geom\u00e9tricas \u00b7 origem %d/%d", i, n))
      append_part(calculate_proximity(resolved$valid[i, , drop = FALSE], request$equipment,
        modes = character(), config = config))
    }
    has_destinations <- nrow(validate_equipment(request$equipment, config)$eligible) > 0L
    for (mode in request$modes) {
      if (!has_destinations) {
        for (i in seq_len(n)) append_part(data.frame())
        next
      }
      publish(paste("Carregando a rede local:", mode))
      graph <- if (is.null(request$graphs)) load_network_graphs(config, mode) else request$graphs[mode]
      if (is.null(graph[[mode]]) || !nrow(graph[[mode]])) stop("Grafo local ausente ou vazio: ", mode)
      for (i in seq_len(n)) {
        publish(sprintf("Rede %s \u00b7 origem %d/%d", mode, i, n))
        result <- calculate_proximity(resolved$valid[i, , drop = FALSE], request$equipment,
          graphs = graph, modes = mode, directions = request$directions, config = config,
          progress_callback = function(stage) publish(sprintf("Rede \u00b7 origem %d/%d \u00b7 %s", i, n, stage)))
        diagnostics <- attr(result, "routing_diagnostics")
        if (nrow(result)) result <- result[result$distance_family == "network", , drop = FALSE]
        if (!is.null(diagnostics)) diagnostics <- diagnostics[grepl("^network_", diagnostics$metric_id), , drop = FALSE]
        attr(result, "routing_diagnostics") <- diagnostics
        append_part(result)
      }
      rm(graph)
      gc(verbose = FALSE)
    }
    publish("C\u00e1lculos conclu\u00eddos", "completed")
  }, error = function(e) publish(conditionMessage(e), "failed"))
  invisible(NULL)
}

web_launch_worker <- function(job_dir) {
  package_path <- getNamespaceInfo(asNamespace("sampamaisrural"), "path")
  source_package <- file.exists(file.path(package_path, "R", "app.R"))
  callr::r_bg(function(request_path, package_path, source_package) {
    if (source_package) pkgload::load_all(package_path, quiet = TRUE)
    else loadNamespace("sampamaisrural", lib.loc = dirname(package_path))
    get("web_job_worker", envir = asNamespace("sampamaisrural"))(request_path)
  }, args = list(request_path = file.path(job_dir, "request.rds"), package_path = package_path,
    source_package = source_package), libpath = .libPaths(), user_profile = FALSE,
    system_profile = FALSE, supervise = TRUE,
    stdout = file.path(job_dir, "worker.log"), stderr = file.path(job_dir, "worker-errors.log"))
}

new_web_pool <- function(launch = web_launch_worker) {
  pool <- new.env(parent = emptyenv())
  pool$jobs <- list()
  pool$active <- NULL
  pool$launch <- launch
  pool
}

web_submit <- function(pool, input, equipment, graphs, config, modes, directions, kind) {
  timeout <- config$web$stage_timeout_seconds %||% 900
  if (length(timeout) != 1L || !is.finite(timeout) || timeout <= 0) stop("web.stage_timeout_seconds deve ser positivo.")
  id <- paste0("web-", new_job_id())
  job_dir <- file.path(config$jobs_dir, id)
  dir.create(job_dir, recursive = TRUE, showWarnings = FALSE)
  # Own the upload: Shiny deletes its temporary upload when the session ends.
  if (is.character(input)) {
    target <- file.path(job_dir, paste0("input.", tools::file_ext(input)))
    if (!file.copy(input, target)) stop("N\u00e3o foi poss\u00edvel guardar o arquivo do lote.")
    input <- target
  }
  atomic_save_rds(list(input = input, equipment = equipment, graphs = graphs,
    config = config, modes = modes, directions = directions), file.path(job_dir, "request.rds"))
  state <- list(job_id = id, kind = kind, status = "queued", stage = "Aguardando a vez na fila local",
    submitted_at = as.numeric(Sys.time()), updated_at = as.numeric(Sys.time()),
    completed_units = 0L, total_units = 0L, parts = character(),
    requested_modes = modes, directions = directions, origins = data.frame(), errors = data.frame())
  web_job_write(state, job_dir)
  pool$jobs[[id]] <- list(dir = job_dir, process = NULL, timeout = timeout)
  id
}

web_stop <- function(pool, id, status = "cancelled", message = "Cancelado pelo usu\u00e1rio") {
  job <- pool$jobs[[id]]
  if (is.null(job)) return(invisible(NULL))
  if (!is.null(job$process) && job$process$is_alive()) {
    # A child can exit between is_alive() and kill_tree(); processx/ps may then
    # report no_such_process. Still verify termination before releasing RAM.
    tryCatch(job$process$kill_tree(), error = function(e) job$process$kill())
    job$process$wait(1000)
    if (job$process$is_alive()) stop("N\u00e3o foi poss\u00edvel encerrar o processo da consulta.")
  }
  state <- web_job_read(job$dir)
  if (!web_terminal(state$status)) {
    state$status <- status
    state$stage <- message
    web_job_write(state, job$dir)
  }
  if (identical(pool$active, id)) pool$active <- NULL
  invisible(NULL)
}

web_poll <- function(pool) {
  id <- pool$active
  if (!is.null(id)) {
    job <- pool$jobs[[id]]
    state <- web_job_read(job$dir)
    if (!job$process$is_alive()) {
      outcome <- tryCatch(job$process$get_result(), error = identity)
      if (!web_terminal(state$status)) web_stop(pool, id, "failed",
        if (inherits(outcome, "error")) conditionMessage(outcome) else "O processo terminou sem concluir a consulta. Veja worker-errors.log.")
      pool$active <- NULL
    } else if (as.numeric(Sys.time()) - state$updated_at > job$timeout) {
      web_stop(pool, id, "failed", paste("Limite de tempo da etapa excedido:", state$stage,
        "\u00b7 Tente menos modos ou ajuste web.stage_timeout_seconds."))
    }
  }
  if (is.null(pool$active)) {
    queued <- names(pool$jobs)[vapply(pool$jobs, function(job) identical(web_job_read(job$dir)$status, "queued"), logical(1))]
    if (length(queued)) {
      id <- queued[[1]]
      state <- web_job_read(pool$jobs[[id]]$dir)
      state$status <- "running"; state$stage <- "Iniciando processo R local"
      web_job_write(state, pool$jobs[[id]]$dir)
      process <- tryCatch(pool$launch(pool$jobs[[id]]$dir), error = identity)
      if (inherits(process, "error")) web_stop(pool, id, "failed", conditionMessage(process))
      else {
        pool$jobs[[id]]$process <- process
        pool$active <- id
      }
    }
  }
  invisible(NULL)
}

web_job_message <- function(state, result) {
  if (state$status == "queued") return("Na fila local: outra consulta est\u00e1 em execu\u00e7\u00e3o. Voc\u00ea pode cancelar a espera.")
  partial <- sprintf("Resultados parciais: %d/%d unidades conclu\u00eddas (origem \u00d7 geometria/modo).",
    state$completed_units, state$total_units)
  if (state$status == "running") return(paste(partial, state$stage,
    "\u00b7", round(as.numeric(Sys.time()) - state$submitted_at), "s decorridos. Mapas e estat\u00edsticas j\u00e1 dispon\u00edveis s\u00e3o parciais."))
  if (state$status != "completed") return(paste(if (state$status == "cancelled") "Consulta cancelada." else "Consulta n\u00e3o realizada integralmente:",
    state$stage, partial))
  if (state$kind == "batch") return(sprintf("Lote conclu\u00eddo: %d origens v\u00e1lidas; %d com erro. Veja mapa e tabelas em Explorar e Estat\u00edsticas.",
    nrow(state$origins), length(unique(state$errors$row))))
  if (!nrow(result)) return("Nenhum equipamento mape\u00e1vel para esses filtros. Amplie os tipos ou remova o filtro de acessibilidade.")
  origin <- state$origins
  note <- if (identical(origin$origin_method[[1]], "cep")) sprintf("CEP aproximado: %.6f, %.6f \u00b7 %s.",
    origin$latitude[1], origin$longitude[1], origin$geocode_source[1]) else "Coordenadas fornecidas."
  sprintf("Consulta conclu\u00edda: %d equipamentos distintos selecionados. %s", length(unique(result$equipment_id)), note)
}

web_batch_bundle <- function(job_dir, state) {
  # Called only at download time, after a terminal state. No private request,
  # original upload, R objects or process logs are included in the ZIP.
  output <- file.path(job_dir, "export")
  dir.create(output, showWarnings = FALSE)
  result <- web_job_results(job_dir, state)
  readr::write_csv(web_export_results(result, state), file.path(output, "results.csv"), na = "")
  readr::write_csv(proximity_summary(result), file.path(output, "statistics.csv"), na = "")
  readr::write_csv(state$errors, file.path(output, "errors.csv"), na = "")
  readr::write_csv(state$origins, file.path(output, "origins.csv"), na = "")
  diagnostics <- attr(result, "routing_diagnostics")
  readr::write_csv(diagnostics, file.path(output, "routing-diagnostics.csv"), na = "")
  for (i in seq_along(state$parts)) {
    part <- readRDS(file.path(job_dir, state$parts[[i]]))
    if (!ncol(part)) part <- data.frame(origin_id = character(), equipment_id = character(),
      metric_id = character(), distance_m = double())
    arrow::write_parquet(part, file.path(output, sprintf("part-%05d.parquet", i)))
  }
  manifest <- state[setdiff(names(state), c("origins", "errors", "parts"))]
  manifest$complete <- identical(state$status, "completed")
  manifest$valid_rows <- nrow(state$origins)
  manifest$error_rows <- length(unique(state$errors$row))
  manifest$partitions <- sub("\\.rds$", ".parquet", state$parts)
  atomic_write_json(manifest, file.path(output, "manifest.json"))
  output
}
