# Step I inputs are generated locally and entirely synthetic.
phase1_check_config <- function(envir = parent.frame()) {
  list(data_dir = file.path(withr::local_tempdir(.local_envir = envir), "synthetic-data"))
}
phase1_check_identity <- function(representation = "json", query = "", source_id = "demo.base") {
  slug <- if (source_id == "demo.base") "base-sintetica" else "recorte-sintetico"
  source_request_identity(source_id, representation, paste0("https://example.invalid/reports/", slug, ".", representation, query),
    phase1_registry())
}
phase1_check_clock <- function() "2030-01-02T03:04:05Z"
phase1_check_event <- function(identity, number = 1L, type = "state_initialized", sha = NULL) {
  source_state_event(type, identity, clock = phase1_check_clock, id = function() paste0("synthetic-event-", number), content_sha256 = sha)
}
phase1_check_commit <- function(config, identity, state, number = 1L, type = "state_initialized", sha = NULL, ...) {
  commit_source_event(config, identity, phase1_check_event(identity, number, type, sha), state, clock = phase1_check_clock, ...)
}
phase1_check_revision <- function(config, identity, number = 1L) {
  source_safe_path(source_operational_root(config), paste0(source_revisions_relative(identity), "/", sprintf("%012d.json", number)))
}
phase1_check_rewrite <- function(path, edit, resign = TRUE) {
  record <- source_read_json(path)
  record <- edit(record)
  if (resign) record$record_sha256 <- source_record_checksum(record)
  source_write_json(record, path)
  invisible(record)
}
phase1_check_validation <- function(decision = "allow") {
  list(decision = decision, classification = if (decision == "block") "breaking" else "valid",
    contract_id = "synthetic.local", contract_version = 1L)
}
# Rebind functions into a self-contained environment so child processes use the
# current source definitions even before the package is installed. No pkgload,
# application, real data or HTTP initialization is required in the children.
phase1_check_lock_api <- function() {
  env <- new.env(parent = baseenv())
  ns <- asNamespace("sampamaisrural")
  symbols <- c(ls(ns, pattern = "^(source_|acquire_source_lock$|assert_source_lock$|release_source_lock$)"), "%||%")
  for (name in symbols) {
    fun <- get(name, ns)
    if (is.function(fun)) { environment(fun) <- env; assign(name, fun, env) }
  }
  env
}
