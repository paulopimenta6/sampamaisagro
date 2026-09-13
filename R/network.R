#' Build routable graphs for requested travel modes
#'
#' @param osm_lines An `sf` LINESTRING object with OpenStreetMap road attributes.
#' @param modes One or more of `foot`, `bicycle`, and `motorcar`.
#' @return Named list of weighted `dodgr` graphs.
#' @export
build_network_graphs <- function(osm_lines, modes = c("foot", "bicycle", "motorcar")) {
  if (!inherits(osm_lines, "sf")) stop("osm_lines deve ser um objeto sf.")
  allowed <- c("foot", "bicycle", "motorcar")
  modes <- match.arg(modes, allowed, several.ok = TRUE)
  lapply_stats <- lapply(modes, function(mode) dodgr::weight_streetnet(osm_lines, wt_profile = mode))
  stats::setNames(lapply_stats, modes)
}

#' Load versioned network graphs
#'
#' @param config Project configuration.
#' @param modes Modes to load.
#' @return Named list; unavailable graphs are omitted.
#' @export
load_network_graphs <- function(config = read_sampa_config(), modes = config$network$modes) {
  files <- file.path(config$data_dir, "processed", paste0("network_", modes, ".rds"))
  present <- file.exists(files)
  graphs <- lapply(files[present], readRDS)
  stats::setNames(graphs, modes[present])
}

read_osm_lines <- function(pbf_path, boundary = NULL) {
  if (!requireNamespace("osmextract", quietly = TRUE)) stop("Instale osmextract para preparar a rede.")
  osmextract::oe_read(
    pbf_path, layer = "lines", boundary = boundary,
    extra_tags = c("maxspeed", "surface", "access", "foot", "bicycle", "motor_vehicle"),
    quiet = FALSE
  )
}

save_network_graphs <- function(graphs, config = read_sampa_config()) {
  ensure_project_dirs(config)
  for (mode in names(graphs)) {
    atomic_save_rds(graphs[[mode]], file.path(config$data_dir, "processed", paste0("network_", mode, ".rds")))
  }
  invisible(graphs)
}
