#!/usr/bin/env Rscript
# Deterministic regressions for capture containment and benchmark timing.
# Only isolated synthetic directories and a simulated clock are used.
capture <- parse("scripts/capture_v02_baseline.R")
load_at <- which(vapply(capture, function(x) is.call(x) &&
  identical(x[[1L]], quote(pkgload::load_all)), logical(1)))
stopifnot(length(load_at) == 1L)
bootstrap <- capture[seq_len(load_at - 1L)]

check_capture_paths <- function() {
  previous <- getwd()
  on.exit(setwd(previous), add = TRUE)
  work <- tempfile("capture-containment-")
  dir.create(file.path(work, "tests", "fixtures", "v02"), recursive = TRUE)
  setwd(work)
  protected <- normalizePath("tests/fixtures/v02", winslash = "/")
  writeLines("approved synthetic sentinel", file.path(protected, "approved.txt"))
  before <- readLines(file.path(protected, "approved.txt"))
  run <- function(argument, forbidden = FALSE) {
    env <- new.env(parent = baseenv())
    env$commandArgs <- function(...) argument
    error <- tryCatch({ eval(bootstrap, env); NULL }, error = identity)
    if (forbidden) {
      stopifnot(inherits(error, "error"))
    } else {
      if (inherits(error, "error")) stop(error)
      stopifnot(startsWith(env$target, paste0(normalizePath(".", winslash = "/"), "/")))
    }
    invisible(env$target)
  }
  # Explicit reported regression, exact directory, absolute paths and dot components.
  for (path in c("tests/fixtures/v02/candidate", protected,
      file.path(protected, "new", "candidate"), "tests/fixtures/v02",
      "tests/fixtures/v02/../v02/candidate", "tests/fixtures/missing/../v02/candidate")) {
    run(path, forbidden = TRUE)
  }
  stopifnot(!dir.exists(file.path(protected, "candidate")))
  for (relative in c(TRUE, FALSE)) for (existing in c(FALSE, TRUE)) {
    path <- file.path("outputs", paste(relative, existing, sep = "-"))
    if (existing) dir.create(path, recursive = TRUE)
    if (!relative) path <- file.path(getwd(), path)
    resolved <- run(path)
    stopifnot(identical(resolved, file.path(normalizePath(".", winslash = "/"),
      "outputs", paste(relative, existing, sep = "-"))))
  }
  # A common text prefix is not containment; missing parents must also resolve.
  run("tests/fixtures/v020/candidate")
  run("outputs/not-yet/nested/candidate")
  dir.create("occupied"); writeLines("preserve", "occupied/evidence.txt")
  run("occupied", forbidden = TRUE)
  run("occupied/evidence.txt", forbidden = TRUE)
  stopifnot(identical(readLines("occupied/evidence.txt"), "preserve"))
  if (.Platform$OS.type == "unix") {
    stopifnot(file.symlink(protected, "fixture-alias"))
    run("fixture-alias/candidate", forbidden = TRUE)
    run("fixture-alias", forbidden = TRUE)
    # A symlink encountered after resolving a nonexistent /.. must not evade the guard.
    run("missing/../fixture-alias/candidate", forbidden = TRUE)
    stopifnot(file.symlink(file.path(getwd(), "outputs"), "outside-alias"))
    run("outside-alias/candidate")
    stopifnot(file.symlink(file.path(protected, "missing"), "dangling-alias"))
    run("dangling-alias/candidate", forbidden = TRUE)
  }
  stopifnot(identical(list.files(protected), "approved.txt"),
    identical(readLines(file.path(protected, "approved.txt")), before))
  cat("PASS: capture paths, protected directory/descendants, boundary, aliases and no overwrite\n")
}

benchmark <- parse("scripts/benchmark_controlled.R")
assignment <- function(code, name) {
  found <- Filter(function(x) is.call(x) && identical(x[[1L]], as.name("<-")) &&
    identical(x[[2L]], as.name(name)), as.list(code))
  stopifnot(length(found) == 1L)
  found[[1L]]
}
case_body <- assignment(benchmark, "benchmark_case")[[3L]][[3L]]
pass_body <- assignment(as.list(case_body)[-1L], "one_pass")[[3L]][[3L]]
statements <- as.list(pass_body)[-1L]
pool_at <- which(vapply(statements, function(x) is.call(x) &&
  identical(x[[1L]], as.name("<-")) && identical(x[[2L]], as.name("pool")), logical(1)))
stopifnot(length(pool_at) == 1L)

simulate_web <- function(gc_cost = 0, verification_cost = 0, mismatch = FALSE) {
  env <- new.env(parent = baseenv())
  env$clock <- 0; env$polls <- 0L; env$verified <- 0L
  env$iteration <- 0L; env$thermal <- "synthetic-clock"
  env$n_origins <- 1L; env$mode <- "motorcar"
  env$eq <- env$origins <- env$direct <- data.frame(value = 1L)
  env$cfg <- env$loaded <- list()
  env$timings <- list(data.frame(stage = "synchronous_complete", iteration = 0L,
    thermal = "synthetic-clock", origins = 1L, destinations = 1L, repeated_origins = FALSE,
    mode = "motorcar", objective = NA_character_, direction = NA_character_,
    elapsed_s = 0, user_s = 0, system_s = 0, r_heap_peak_mb = 0,
    process_lifetime_peak_rss_mb = 0, result_bytes = 0))
  env$repeated <- FALSE
  env$proc.time <- function() c(user.self = 0, sys.self = 0, elapsed = env$clock,
    user.child = 0, sys.child = 0)
  env$gc <- function(...) { env$clock <- env$clock + gc_cost; matrix(0, 2, 6) }
  env$rss <- function() 0
  env$object.size <- function(...) 0
  env$Sys.sleep <- function(time) env$clock <- env$clock + time
  env$v02_projection <- function(x) {
    env$clock <- env$clock + verification_cost
    env$verified <- env$verified + 1L
    x
  }
  env$v02_internal <- function(name) switch(name,
    new_web_pool = function() list(jobs = list(fixture = list(dir = "synthetic-job"))),
    web_submit = function(...) { env$clock <- env$clock + 2; "fixture" },
    web_poll = function(...) {
      env$polls <- env$polls + 1L
      env$clock <- env$clock + if (env$polls == 1L) 3 else 4
      invisible(NULL)
    },
    web_job_read = function(...) list(parts = "part", status = if (env$polls < 3L) "running" else "completed"),
    web_terminal = function(status) status == "completed",
    web_job_results = function(...) { env$clock <- env$clock + 5; data.frame(value = if (mismatch) 2L else 1L) },
    web_stop = function(...) invisible(NULL),
    stop("Unexpected worker call: ", name))
  # Run the actual web section, not a separate implementation of the timing contract.
  eval(assignment(as.list(case_body)[-1L], "measure"), env)
  execute <- function() NULL
  body(execute) <- as.call(c(list(as.name("{")), statements[seq.int(pool_at, length(statements))]))
  environment(execute) <- env
  execute()
  stopifnot(env$verified == 2L)
  rows <- do.call(rbind, env$timings)
  rows <- rows[startsWith(rows$stage, "web_"), c("stage", "elapsed_s")]
  rownames(rows) <- NULL
  rows
}

check_web_timing <- function() {
  baseline <- simulate_web()
  # Expensive forced GC and projections must not change any web latency metric.
  stopifnot(isTRUE(all.equal(baseline, simulate_web(verification_cost = 1000))))
  stopifnot(isTRUE(all.equal(baseline, simulate_web(gc_cost = 500))))
  expected <- c(web_submit = 2, web_launch = 3, web_result_read = 5,
    web_first_part = 9, web_completion = 13.02, web_total = 18.02)
  measured <- setNames(baseline$elapsed_s, baseline$stage)
  stopifnot(isTRUE(all.equal(unname(measured[names(expected)]), unname(expected), tolerance = 1e-8)))
  rejected <- tryCatch({ simulate_web(mismatch = TRUE); FALSE }, error = function(e) TRUE)
  stopifnot(rejected)
  cat("PASS: web timing excludes forced GC/verification; mismatched results still fail\n")
}

check_capture_paths()
check_web_timing()
