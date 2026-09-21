#!/usr/bin/env Rscript
# Compare R version objects: e.g. 1.30.2-1 and 1.30.2.1 denote the same version.
# Reading package metadata does not load packages or access the network.
check_locked_versions <- function(lockfile = "renv.lock", version_for = utils::packageVersion) {
  lock <- tryCatch(jsonlite::read_json(lockfile), error = function(e) {
    stop("Cannot read lockfile ", lockfile, ": ", conditionMessage(e), call. = FALSE)
  })
  packages <- if (is.list(lock)) lock[["Packages"]] else NULL
  package_names <- names(packages)
  if (!is.list(packages) || !length(packages) || is.null(package_names) ||
      anyNA(package_names) || any(!nzchar(package_names)) || anyDuplicated(package_names)) {
    stop("Invalid lockfile Packages: expected a nonempty object with unique package names.", call. = FALSE)
  }
  for (pkg in package_names) {
    record <- packages[[pkg]]
    version <- if (is.list(record)) record[["Version"]] else NULL
    invalid <- function() stop("Invalid lockfile Version for ", pkg,
      ": expected one nonempty R package version string.", call. = FALSE)
    if (!is.character(version) || length(version) != 1L || is.na(version) || !nzchar(version)) invalid()
    expected <- tryCatch(package_version(version), error = function(e) invalid())
    installed <- tryCatch(version_for(pkg), error = function(e) {
      stop("Cannot read installed version for ", pkg, ": ", conditionMessage(e), call. = FALSE)
    })
    if (!isTRUE(installed == expected)) {
      stop("Version mismatch for ", pkg, ": installed ", as.character(installed),
        ", locked ", version, ".", call. = FALSE)
    }
  }
  message("Locked versions verified semantically: ", length(packages), " packages.")
  invisible(TRUE)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) > 1L) stop("Usage: Rscript scripts/ci/check-locked-versions.R [renv.lock]")
  check_locked_versions(if (length(args)) args[[1L]] else "renv.lock")
}
