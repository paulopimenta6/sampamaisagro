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
  lapply_stats <- lapply(modes, function(mode) {
    lines <- osm_lines
    if (!"oneway" %in% names(lines)) lines$oneway <- rep(NA_character_, nrow(lines))
    direction <- tolower(as.character(lines$oneway))
    reverse <- which(!is.na(direction) & direction == "-1")
    if (length(reverse)) {
      geometry <- sf::st_geometry(lines)
      geometry[reverse] <- sf::st_sfc(lapply(geometry[reverse], function(g) {
        xy <- sf::st_coordinates(g)[, 1:2, drop = FALSE]
        sf::st_linestring(xy[nrow(xy):1, , drop = FALSE])
      }), crs = sf::st_crs(lines))
      sf::st_geometry(lines) <- geometry
    }
    explicit_no <- !is.na(direction) & direction %in% c("no", "false", "0")
    one_way <- !is.na(direction) & direction %in% c("yes", "true", "1", "-1")
    if ("junction" %in% names(lines)) one_way <- one_way |
      (!explicit_no & !is.na(lines$junction) & lines$junction %in% c("roundabout", "circular"))
    uncertain <- !is.na(direction) & !direction %in% c("", "no", "false", "0", "yes", "true", "1", "-1")
    lines$oneway <- ifelse(one_way & mode != "foot", "yes", "no")
    # Variable-direction lanes cannot be assigned a defensible fixed direction.
    keep <- if (mode == "foot") rep(TRUE, nrow(lines)) else !uncertain
    tag <- if (mode == "motorcar") "motor_vehicle" else mode
    specific <- if (tag %in% names(lines)) tolower(lines[[tag]]) else rep(NA_character_, nrow(lines))
    general <- if ("access" %in% names(lines)) tolower(lines$access) else rep(NA_character_, nrow(lines))
    prohibited <- !is.na(specific) & specific %in% c("no", "private")
    prohibited <- prohibited | (!is.na(general) & general %in% c("no", "private") &
      !(specific %in% c("yes", "designated", "permissive")))
    lines <- lines[keep & !prohibited, , drop = FALSE]
    graph <- dodgr::weight_streetnet(lines, wt_profile = mode)
    # Profile penalties encode preferences, not physical shortest/fastest paths.
    graph$d_weighted <- graph$d
    graph$time_weighted <- graph$time
    attr(graph, "direction_access_policy") <- "v2: reversed -1; foot bidirectional; roundabout; explicit private/no excluded; variable oneway excluded for vehicles"
    graph
  })
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
