#!/usr/bin/env Rscript
# Measurement only: no production optimizations, downloads, or real data.
args <- commandArgs(trailingOnly = TRUE)
Sys.setenv(TZ = "UTC")
smoke <- "--smoke" %in% args
args <- setdiff(args, "--smoke")
if (length(args) != 1L) stop("Usage: Rscript scripts/benchmark_controlled.R [--smoke] NEW_OUTPUT_DIRECTORY")
out <- normalizePath(args[[1]], mustWork = FALSE)
if (file.exists(out) || dir.exists(out)) stop("Output exists; benchmark never overwrites a run.")
root <- normalizePath(".")
fixtures <- normalizePath("tests/fixtures/v02")
dir.create(out, recursive = TRUE)

benchmark_case <- function(root, fixtures, n_origins, n_destinations, repeated, mode, repetitions) {
  pkgload::load_all(root, quiet = TRUE)
  source(file.path(fixtures, "load.R"), local = TRUE)
  work <- tempfile("v02-benchmark-"); dir.create(work)
  cfg <- v02_config(work, fixtures)
  v02_internal("ensure_project_dirs")(cfg)
  grid <- expand.grid(x = 0:19, y = 0:19)
  vertices <- data.frame(id = as.character(seq_len(nrow(grid))),
    longitude = -46.812345 + grid$x * 0.001, latitude = -23.712345 + grid$y * 0.0009)
  edges <- do.call(rbind, lapply(seq_len(nrow(grid)), function(i) {
    next_ids <- which(abs(grid$x - grid$x[i]) + abs(grid$y - grid$y[i]) == 1)
    data.frame(from_id = as.character(i), to_id = as.character(next_ids), d = 110,
      time = (if (mode == "foot") 110 else if (mode == "bicycle") 33 else 15) +
        ifelse(next_ids > i, 0, 7))
  }))
  graph <- v02_graph_from_tables(vertices, edges)
  graph_path <- file.path(work, "graph.rds"); saveRDS(graph, graph_path)
  ids <- unique(as.integer(round(seq(1, nrow(vertices), length.out = n_destinations))))
  eq <- data.frame(equipment_id = paste0("bench-", ids), equipment_name = paste("Synthetic", ids),
    category = "Fixture", postal_code = NA_character_, snapshot_date = "synthetic-grid-20",
    longitude = vertices$longitude[ids], latitude = vertices$latitude[ids])
  from <- if (repeated) rep(1L, n_origins) else seq_len(n_origins)
  origins <- data.frame(query_id = paste0("bench-origin-", seq_len(n_origins)),
    latitude = vertices$latitude[from], longitude = vertices$longitude[from], k = 10L, radius_m = 150)
  timings <- list(); iteration <- 0L; thermal <- "process_first_pass"
  rss <- function() {
    if (!file.exists("/proc/self/status")) return(NA_real_)
    line <- grep("^VmHWM:", readLines("/proc/self/status"), value = TRUE)
    if (!length(line)) return(NA_real_)
    as.numeric(gsub("[^0-9]", "", line)) / 1024
  }
  measure <- function(stage, code, objective = NA_character_, direction = NA_character_) {
    gc(reset = TRUE)
    before <- proc.time()
    value <- force(code)
    elapsed <- proc.time() - before
    memory <- gc()
    timings[[length(timings) + 1L]] <<- data.frame(stage = stage, iteration = iteration,
      thermal = thermal, origins = n_origins, destinations = nrow(eq), repeated_origins = repeated,
      mode = mode, objective = objective, direction = direction,
      elapsed_s = unname(elapsed["elapsed"]), user_s = unname(elapsed["user.self"]),
      system_s = unname(elapsed["sys.self"]), r_heap_peak_mb = sum(memory[, 6]),
      process_lifetime_peak_rss_mb = rss(), result_bytes = as.numeric(object.size(value)))
    value
  }
  one_pass <- function() {
    loaded <- measure("graph_read", readRDS(graph_path))
    eligible <- measure("destination_validation", sampamaisrural::validate_equipment(eq, cfg)$eligible)
    verts <- measure("vertices", dodgr::dodgr_vertices(loaded))
    matched <- measure("destination_snapping", v02_internal("match_graph_points")(
      loaded, eligible[, c("longitude", "latitude")], verts))
    resolved <- sampamaisrural::resolve_origins(origins, cfg)$valid
    names(resolved)[names(resolved) == "query_id"] <- "origin_id"
    origin_matches <- measure("origin_snapping", lapply(seq_len(n_origins), function(i)
      v02_internal("match_graph_points")(loaded, resolved[i, c("longitude", "latitude")], verts)))
    measure("geometry", lapply(seq_len(n_origins), function(i) v02_internal("geometric_distance_matrix")(
      resolved$longitude[i], resolved$latitude[i], eligible, cfg$spatial$projected_crs)))
    for (objective in c("shortest", "fastest")) for (direction in c("origin_to_equipment", "equipment_to_origin")) {
      measure("network_cost", lapply(seq_len(n_origins), function(i) v02_internal("route_one_direction")(
        loaded, resolved[i, ], eligible, mode, objective, direction, 10, 150, 250, 1000,
        c(foot = 3.6, bicycle = 12, motorcar = 30)[[mode]],
        matches = list(origin = origin_matches[[i]], equipment = matched))), objective, direction)
    }
    direct <- measure("synchronous_complete", sampamaisrural::calculate_proximity(
      sampamaisrural::resolve_origins(origins, cfg)$valid, eq,
      setNames(list(loaded), mode), modes = mode, directions = "both", config = cfg))
    pool <- v02_internal("new_web_pool")()
    id <- NULL; first <- NULL
    on.exit(if (!is.null(id)) v02_internal("web_stop")(pool, id), add = TRUE)
    # Stabilize before timing. No measure(), forced GC or row/projection work
    # belongs inside the end-to-end web interval.
    gc(reset = TRUE)
    start <- proc.time()
    id <- v02_internal("web_submit")(pool, origins, eq,
      setNames(list(loaded), mode), cfg, mode, "both", "batch")
    submitted <- proc.time()
    v02_internal("web_poll")(pool)
    launched <- proc.time()
    repeat {
      v02_internal("web_poll")(pool)
      state <- v02_internal("web_job_read")(pool$jobs[[id]]$dir)
      observed <- proc.time()
      if (length(state$parts) && is.null(first)) first <- observed
      if (v02_internal("web_terminal")(state$status)) break
      if ((observed - start)[["elapsed"]] > 900) stop("Synthetic benchmark worker timeout")
      Sys.sleep(0.02)
    }
    if (state$status != "completed") stop(state$stage)
    read_started <- proc.time()
    actual <- v02_internal("web_job_results")(pool$jobs[[id]]$dir)
    finished <- proc.time() # Functional result is available: stop before instrumentation.
    web_memory <- gc()
    web_rss <- rss()
    stopifnot(isTRUE(all.equal(v02_projection(direct), v02_projection(actual), tolerance = 1e-8)))
    intervals <- list(web_submit = submitted - start, web_launch = launched - submitted,
      web_result_read = finished - read_started, web_completion = observed - start,
      web_total = finished - start, web_first_part = if (is.null(first)) (start - start) * NA_real_ else first - start)
    prototype <- timings[[length(timings)]]
    for (stage in names(intervals)) {
      row <- prototype
      row$stage <- stage
      elapsed <- intervals[[stage]]
      row$elapsed_s <- unname(elapsed["elapsed"])
      row$user_s <- unname(elapsed["user.self"])
      row$system_s <- unname(elapsed["sys.self"])
      # Web memory is measured for the complete interval, not individual stages.
      row$r_heap_peak_mb <- if (stage == "web_total") sum(web_memory[, 6]) else NA_real_
      row$process_lifetime_peak_rss_mb <- if (stage == "web_total") web_rss else NA_real_
      row$result_bytes <- if (stage %in% c("web_total", "web_result_read")) as.numeric(object.size(actual)) else NA_real_
      timings[[length(timings) + 1L]] <<- row
    }
    invisible(NULL)
  }
  # First pass is recorded separately; it warms the process, not the OS cache.
  one_pass()
  thermal <- "warm"
  for (i in seq_len(repetitions)) { iteration <- i; one_pass() }
  list(timings = do.call(rbind, timings), graph = list(vertices = nrow(vertices), edges = nrow(edges),
    source_hash = digest::digest(list(vertices, edges), algo = "sha256"),
    file_hash = v02_internal("sha256_file")(graph_path)),
    inputs_hash = digest::digest(list(origins, eq, cfg$spatial, cfg$proximity), algo = "sha256"),
    spatial_libraries = as.list(sf::sf_extSoftVersion()),
    environment = list(r_version = R.version.string, platform = R.version$platform,
      timezone = Sys.getenv("TZ"), packages = as.list(setNames(vapply(loadedNamespaces(),
        function(p) as.character(utils::packageVersion(p)), character(1)), loadedNamespaces()))))
}

cases <- expand.grid(origins = if (smoke) 1L else c(1L, 10L, 100L),
  destinations = if (smoke) 25L else c(25L, 100L, 400L),
  repeated = if (smoke) FALSE else c(FALSE, TRUE),
  mode = if (smoke) "motorcar" else c("foot", "bicycle", "motorcar"), stringsAsFactors = FALSE)
metadata <- list()
for (i in seq_len(nrow(cases))) {
  case <- cases[i, ]
  message("Synthetic benchmark case ", i, "/", nrow(cases))
  result <- callr::r(benchmark_case, args = list(root, fixtures, case$origins,
    case$destinations, case$repeated, case$mode, if (smoke) 1L else 5L),
    user_profile = FALSE, system_profile = FALSE)
  readr::write_csv(result$timings, file.path(out, sprintf("case-%03d.csv", i)))
  result$timings <- NULL
  metadata[[i]] <- c(as.list(case), result)
}
all <- dplyr::bind_rows(lapply(list.files(out, pattern = "^case-.*csv$", full.names = TRUE),
  function(p) readr::read_csv(p, show_col_types = FALSE)))
summary <- all[all$thermal == "warm", ] |>
  dplyr::group_by(stage, origins, destinations, repeated_origins, mode, objective, direction) |>
  dplyr::summarise(repetitions = dplyr::n(), median_s = stats::median(elapsed_s),
    iqr_s = stats::IQR(elapsed_s), .groups = "drop")
readr::write_csv(summary, file.path(out, "summary.csv"))
files <- c(list.files(file.path(root, "R"), full.names = TRUE, pattern = "\\.R$"),
  file.path(root, "renv.lock"), file.path(root, "scripts", "benchmark_controlled.R"),
  list.files(fixtures, full.names = TRUE, recursive = TRUE))
hashes <- setNames(vapply(files, function(p) digest::digest(file = p, algo = "sha256", serialize = FALSE),
  character(1)), substring(files, nchar(root) + 2L))
jsonlite::write_json(list(synthetic = TRUE, smoke = smoke, cases = metadata,
  commit = system2("git", c("rev-parse", "HEAD"), stdout = TRUE),
  git_status = system2("git", c("status", "--porcelain"), stdout = TRUE), hashes = as.list(hashes),
  hardware = as.list(Sys.info()), logical_cores = parallel::detectCores(),
  memory_note = "R heap maxima by stage, or over the whole web interval for web_total; web component memory is NA. RSS is process-lifetime high-water mark, not summed parent/child memory. CPU times are parent-process self time.",
  cold_note = "Fresh R process per case; first pass is also warmup. OS caches are not cleared.",
  overhead_note = "Compare web_total with synchronous_complete; includes submission, process startup, serialization, I/O, observed polling and functional result reading. Forced instrumentation GC, row construction, projections, sorting, equivalence and comparison hashing are outside the interval. Automatic runtime GC remains part of execution.",
  web_metric_definitions = list(web_submit = "Submission and request serialization, with pool already created.",
    web_launch = "First controller poll that initiates worker startup; does not imply worker readiness.",
    web_first_part = "Submission start to first observed published part; not first UI rendering; NA if never observed.",
    web_completion = "Submission start to observed completed worker state, before functional result reading.",
    web_result_read = "Reading and assembling the final functional results through web_job_results.",
    web_total = "Submission start through functional result availability, before benchmark instrumentation and verification.",
    synchronous_complete = "Origin resolution and the complete synchronous calculate_proximity call; forced instrumentation GC and result verification excluded."),
  no_performance_threshold = TRUE), file.path(out, "manifest.json"), pretty = TRUE, auto_unbox = TRUE)
capture.output(sessionInfo(), file = file.path(out, "session-info.txt"))
message("Benchmark complete: ", out)
