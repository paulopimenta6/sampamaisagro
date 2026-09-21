#!/usr/bin/env Rscript
# Exercise the same validator used after renv restore, without installing packages.
source("scripts/ci/check-locked-versions.R", local = TRUE)
work <- tempfile("locked-versions-")
dir.create(work)
lockfile <- file.path(work, "renv.lock")
write_lock <- function(packages) {
  jsonlite::write_json(list(Packages = packages), lockfile, auto_unbox = TRUE)
}
reject <- function(code, message) {
  error <- tryCatch({ force(code); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(message, conditionMessage(error), fixed = TRUE))
}
write_lock(list(AsioHeaders = list(Version = "1.30.2-1"), Simple = list(Version = "1.2.3")))
seen <- character()
installed <- function(pkg) {
  seen <<- c(seen, pkg)
  package_version(if (pkg == "AsioHeaders") "1.30.2.1" else "1.2.3")
}
stopifnot(isTRUE(check_locked_versions(lockfile, version_for = installed)),
  identical(seen, c("AsioHeaders", "Simple")))
reject(check_locked_versions(lockfile, version_for = function(pkg) package_version("1.30.2.2")),
  "Version mismatch for AsioHeaders")
write_lock(list(Simple = list(Version = "1.2.3")))
reject(check_locked_versions(lockfile, version_for = function(pkg) package_version("1.2.4")),
  "Version mismatch for Simple")
empty_library <- file.path(work, "empty-library")
dir.create(empty_library)
reject(check_locked_versions(lockfile,
  version_for = function(pkg) utils::packageVersion(pkg, lib.loc = empty_library)),
  "Cannot read installed version for Simple")
for (invalid in list(NULL, NA_character_, "", "not-a-version", 123, c("1.2.3", "1.2.4"))) {
  write_lock(list(Simple = list(Version = invalid)))
  reject(check_locked_versions(lockfile, version_for = installed), "Invalid lockfile Version for Simple")
}
for (invalid in list(NULL, list(), list(list(Version = "1.2.3")))) {
  write_lock(invalid)
  reject(check_locked_versions(lockfile, version_for = installed), "Invalid lockfile Packages")
}
# write_json() repairs duplicate keys; use literal JSON to test the invalid input.
writeLines('{"Packages":{"Simple":{"Version":"1.2.3"},"Simple":{"Version":"1.2.4"}}}', lockfile)
reject(check_locked_versions(lockfile, version_for = installed), "Invalid lockfile Packages")
cat("PASS: semantic versions (hyphen/dot and simple), mismatches, absent package and invalid lock entries\n")
