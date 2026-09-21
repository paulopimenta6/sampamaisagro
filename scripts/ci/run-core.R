#!/usr/bin/env Rscript
# Run source and installed-package checks without exposing the real data tree.
args <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(".", mustWork = TRUE)
out <- if (length(args)) normalizePath(args[[1]], mustWork = FALSE) else tempfile("phase0-core-")
if (file.exists(out) && (!dir.exists(out) ||
    length(list.files(out, all.files = TRUE, no.. = TRUE)) > 0L)) {
  stop("Use a new or empty output directory; historical evidence is never overwritten.")
}
dir.create(out, recursive = TRUE, showWarnings = FALSE)
# A new relative path can only be canonicalized after its directory exists.
out <- normalizePath(out, mustWork = TRUE)
stage <- file.path(out, "source"); dir.create(stage)
sys.source(file.path(root, "scripts", "ci", "test-core-paths.R"), envir = new.env())
sys.source(file.path(root, "scripts", "ci", "test-phase0-tools.R"), envir = new.env())
sys.source(file.path(root, "scripts", "ci", "test-locked-versions.R"), envir = new.env())
entries <- c("R", "man", "inst", "tests", "scripts", "DESCRIPTION", "NAMESPACE",
  "LICENSE", "LICENSE.md", ".Rbuildignore", "renv.lock")
entries <- entries[file.exists(file.path(root, entries))]
stopifnot(all(file.copy(file.path(root, entries), stage, recursive = TRUE)))
stopifnot(!dir.exists(file.path(stage, "data")), !file.exists(file.path(stage, ".Rprofile")))
# R CMD check otherwise queries available.packages() even with CRAN incoming
# checks disabled. Dependencies were restored before this offline phase.
profile <- file.path(out, "offline-profile.R")
writeLines("options(repos = character())", profile)
options(repos = character())
Sys.setenv(R_PROFILE_USER = "/dev/null", SAMPA_TEST_OFFLINE = "1", TZ = "UTC",
  R_PROFILE = profile,
  RENV_CONFIG_AUTOLOADER_ENABLED = "FALSE", R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
  `_R_CHECK_CRAN_INCOMING_` = "false", `_R_CHECK_CRAN_INCOMING_REMOTE_` = "false")
if (!rmarkdown::pandoc_available()) stop("Pandoc is mandatory: HTML regression must not be skipped.")
required <- c("testthat", "withr", "dodgr", "sf", "arrow", "rmarkdown", "knitr", "tidyr", "spdep", "MASS")
stopifnot(all(vapply(required, requireNamespace, logical(1), quietly = TRUE)))
setwd(stage)
tests <- testthat::test_local(reporter = "summary", stop_on_failure = TRUE)
saveRDS(tests, file.path(out, "testthat-results.rds"))
run <- function(command, arguments, log) {
  status <- system2(command, arguments, stdout = log, stderr = log)
  if (status != 0L) stop("Command failed: ", command, " ", paste(arguments, collapse = " "), "; see ", log)
}
setwd(out)
run(file.path(R.home("bin"), "R"), c("CMD", "build", "--no-build-vignettes", shQuote(stage)), file.path(out, "build.log"))
archive <- list.files(out, pattern = "^sampamaisrural_.*\\.tar\\.gz$", full.names = TRUE)
stopifnot(length(archive) == 1L)
run(file.path(R.home("bin"), "R"), c("CMD", "check", "--no-manual", "--no-build-vignettes", shQuote(archive)), file.path(out, "check.log"))
check <- readLines(file.path(out, "sampamaisrural.Rcheck", "00check.log"), warn = FALSE)
if (any(grepl("[0-9]+ (ERROR|WARNING)", check))) stop("R CMD check reported errors or warnings.")
setwd(root)
run(file.path(R.home("bin"), "Rscript"), c("scripts/benchmark_controlled.R", "--smoke",
  shQuote(file.path(out, "benchmark-smoke"))), file.path(out, "benchmark.log"))
capture.output(sessionInfo(), file = file.path(out, "session-info.txt"))
message("CORE completed; evidence: ", out)
