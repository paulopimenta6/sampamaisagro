#!/usr/bin/env Rscript
# Deterministic runner regression, using only isolated directories and base R.
# Run from the repository root. scripts/ is intentionally excluded from the package.
runner <- parse("scripts/ci/run-core.R")
stage_assignment <- which(vapply(runner, function(expr) is.call(expr) &&
  identical(expr[[1L]], as.name("<-")) && identical(expr[[2L]], as.name("stage")), logical(1)))
stopifnot(length(stage_assignment) == 1L)
# Exercise the actual bootstrap before staging/tests, without recursively running CORE.
bootstrap <- runner[seq_len(stage_assignment - 1L)]
work <- tempfile("core-path-regression-")
dir.create(work)
work <- normalizePath(work, mustWork = TRUE)

check_path <- function(relative, existing) {
  previous <- getwd()
  on.exit(setwd(previous), add = TRUE)
  case <- file.path(work, paste(relative, existing, sep = "-"))
  dir.create(case)
  setwd(case)
  expected <- file.path(case, "outputs", "core-new")
  if (existing) dir.create(expected, recursive = TRUE)
  argument <- if (relative) file.path("outputs", "core-new") else expected
  env <- new.env(parent = baseenv())
  env$commandArgs <- function(...) argument
  eval(bootstrap, env)
  stopifnot(identical(env$out, normalizePath(expected, mustWork = TRUE)))
  # This is the failure point of the former relative path after setwd(stage).
  stage <- file.path(env$out, "source")
  dir.create(stage)
  setwd(stage)
  evidence <- file.path(env$out, "path-check.rds")
  saveRDS(list(passed = TRUE), evidence)
  stopifnot(isTRUE(readRDS(file.path(expected, "path-check.rds"))$passed))
  # A second invocation must preserve the existing evidence rather than overwrite it.
  setwd(case)
  rejected <- tryCatch({ eval(bootstrap, env); FALSE }, error = function(e) TRUE)
  stopifnot(rejected, isTRUE(readRDS(evidence)$passed))
  # An existing regular file is not an output directory either.
  argument <- "existing-file"
  writeLines("preserve", argument)
  rejected <- tryCatch({ eval(bootstrap, env); FALSE }, error = function(e) TRUE)
  stopifnot(rejected, identical(readLines(argument), "preserve"))
  cat("PASS:", if (relative) "relative" else "absolute",
    if (existing) "existing empty directory" else "new directory", "\n")
}

for (relative in c(TRUE, FALSE)) for (existing in c(FALSE, TRUE)) {
  check_path(relative, existing)
}
