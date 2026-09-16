distance_metric_labels <- c(
  geodesic_karney = "Geodesica elipsoidal (Karney)",
  geodesic_haversine = "Haversine esferica",
  euclidean_projected = "Euclidiana projetada",
  manhattan_projected = "Manhattan projetada",
  chebyshev_projected = "Chebyshev projetada"
)

geometric_distance_matrix <- function(origin_lon, origin_lat, destinations, projected_crs = 31983) {
  if (!nrow(destinations)) return(matrix(numeric(), nrow = 0L, ncol = length(distance_metric_labels)))
  origin_ll <- matrix(c(origin_lon, origin_lat), ncol = 2L)
  dest_ll <- as.matrix(destinations[, c("longitude", "latitude"), drop = FALSE])
  origin_repeated <- origin_ll[rep(1L, nrow(dest_ll)), , drop = FALSE]

  ll_sf <- sf::st_as_sf(
    data.frame(longitude = c(origin_lon, dest_ll[, 1]), latitude = c(origin_lat, dest_ll[, 2])),
    coords = c("longitude", "latitude"), crs = 4326, remove = FALSE
  )
  xy <- sf::st_coordinates(sf::st_transform(ll_sf, projected_crs))
  dx <- abs(xy[-1L, 1L] - xy[1L, 1L])
  dy <- abs(xy[-1L, 2L] - xy[1L, 2L])

  out <- cbind(
    geodesic_karney = as.numeric(geosphere::distGeo(origin_repeated, dest_ll)),
    geodesic_haversine = as.numeric(geosphere::distHaversine(origin_repeated, dest_ll)),
    euclidean_projected = sqrt(dx^2 + dy^2),
    manhattan_projected = dx + dy,
    chebyshev_projected = pmax(dx, dy)
  )
  out
}

rank_distance_rows <- function(data, k, radius_m) {
  order_value <- if (nrow(data) && identical(data$path_objective[[1]], "fastest")) data$duration_min else data$distance_m
  data <- data[order(order_value, data$equipment_id, na.last = TRUE), , drop = FALSE]
  reachable <- is.finite(data$distance_m)
  data$rank <- NA_integer_
  data$rank[reachable] <- seq_len(sum(reachable))
  data$within_radius <- reachable & data$distance_m <= radius_m
  data$selected <- data$within_radius | (!is.na(data$rank) & data$rank <= k)
  data
}

geometric_rows <- function(origin, equipment, k, radius_m, projected_crs) {
  matrix_dist <- geometric_distance_matrix(
    origin$longitude[[1]], origin$latitude[[1]], equipment, projected_crs
  )
  rows <- lapply(seq_len(ncol(matrix_dist)), function(j) {
    metric <- colnames(matrix_dist)[j]
    out <- data.frame(
      origin_id = origin$origin_id[[1]],
      equipment_id = equipment$equipment_id,
      metric_id = metric,
      metric_label = unname(distance_metric_labels[[metric]]),
      distance_family = "geometric",
      mode = NA_character_, path_objective = NA_character_, direction = "symmetric",
      distance_m = matrix_dist[, j], duration_min = NA_real_,
      origin_snap_m = 0, equipment_snap_m = 0,
      routing_status = "not_applicable", stringsAsFactors = FALSE
    )
    rank_distance_rows(out, k, radius_m)
  })
  dplyr::bind_rows(rows)
}

match_graph_points <- function(graph, xy, vertices = NULL) {
  vertices <- vertices %||% dodgr::dodgr_vertices(graph)
  xy <- as.data.frame(xy)
  names(xy)[1:2] <- c("x", "y")
  index <- dodgr::match_pts_to_verts(vertices, xy, connected = FALSE)
  snapped <- as.matrix(vertices[index, c("x", "y"), drop = FALSE])
  input <- as.matrix(xy[, c("x", "y"), drop = FALSE])
  list(
    id = vertices$id[index],
    distance = as.numeric(geosphere::distGeo(input[, 1:2, drop = FALSE], snapped[, 1:2, drop = FALSE])),
    snapped_x = snapped[, 1], snapped_y = snapped[, 2]
  )
}

route_one_direction <- function(graph, origin, equipment, mode, objective, direction,
                                k, radius_m, snap_warning_m, snap_exclude_m,
                                connector_speed_kmh, matches = NULL) {
  origin_xy <- matrix(c(origin$longitude[[1]], origin$latitude[[1]]), ncol = 2L)
  equipment_xy <- as.matrix(equipment[, c("longitude", "latitude"), drop = FALSE])
  origin_match <- if (is.null(matches)) match_graph_points(graph, origin_xy) else matches$origin
  equipment_match <- if (is.null(matches)) match_graph_points(graph, equipment_xy) else matches$equipment
  shortest <- identical(objective, "shortest")

  if (identical(direction, "origin_to_equipment")) {
    values <- if (shortest) {
      dodgr::dodgr_dists(graph, from = origin_match$id, to = equipment_match$id,
        shortest = TRUE, parallel = FALSE, quiet = TRUE)
    } else {
      dodgr::dodgr_dists(graph, from = origin_match$id, to = equipment_match$id,
        shortest = FALSE, parallel = FALSE, quiet = TRUE)
    }
    times <- if (shortest) NULL else dodgr::dodgr_times(
      graph, from = origin_match$id, to = equipment_match$id, shortest = FALSE, pairwise = FALSE
    )
  } else {
    values <- if (shortest) {
      dodgr::dodgr_dists(graph, from = equipment_match$id, to = origin_match$id,
        shortest = TRUE, parallel = FALSE, quiet = TRUE)
    } else {
      dodgr::dodgr_dists(graph, from = equipment_match$id, to = origin_match$id,
        shortest = FALSE, parallel = FALSE, quiet = TRUE)
    }
    times <- if (shortest) NULL else dodgr::dodgr_times(
      graph, from = equipment_match$id, to = origin_match$id, shortest = FALSE, pairwise = FALSE
    )
  }
  distance_m <- as.numeric(values)
  duration_min <- if (is.null(times)) rep(NA_real_, length(distance_m)) else as.numeric(times) / 60
  connector_m <- origin_match$distance[[1]] + equipment_match$distance
  distance_m <- distance_m + connector_m
  if (!is.null(times)) duration_min <- duration_min + connector_m / (connector_speed_kmh * 1000 / 60)

  excluded <- origin_match$distance[[1]] > snap_exclude_m | equipment_match$distance > snap_exclude_m
  distance_m[excluded] <- NA_real_
  duration_min[excluded] <- NA_real_
  status <- rep("ok", nrow(equipment))
  status[origin_match$distance[[1]] > snap_warning_m | equipment_match$distance > snap_warning_m] <- "snap_warning"
  status[excluded] <- "snap_excluded"
  status[!excluded & !is.finite(distance_m)] <- "unreachable"

  metric_id <- paste("network", mode, objective, sep = "_")
  out <- data.frame(
    origin_id = origin$origin_id[[1]], equipment_id = equipment$equipment_id,
    metric_id = metric_id,
    metric_label = sprintf("Rede %s - %s", mode, ifelse(shortest, "menor distancia", "menor tempo")),
    distance_family = "network", mode = mode, path_objective = objective, direction = direction,
    distance_m = distance_m, duration_min = duration_min,
    origin_snap_m = origin_match$distance[[1]], equipment_snap_m = equipment_match$distance,
    routing_status = status, stringsAsFactors = FALSE
  )
  rank_distance_rows(out, k, radius_m)
}

network_rows <- function(origin, equipment, graphs, modes, directions, k, radius_m, config,
                         progress_callback = NULL) {
  speeds <- c(foot = 3.6, bicycle = 12, motorcar = 30)
  rows <- list()
  cursor <- 0L
  for (mode in intersect(modes, names(graphs))) {
    if (is.function(progress_callback)) progress_callback(paste(mode, "associando pontos \u00e0s vias"))
    graph <- graphs[[mode]]
    if (is.null(graph) || !nrow(graph)) next
    vertices <- dodgr::dodgr_vertices(graph)
    matches <- list(origin = match_graph_points(graph,
      matrix(c(origin$longitude[[1]], origin$latitude[[1]]), ncol = 2), vertices),
      equipment = match_graph_points(graph, equipment[, c("longitude", "latitude")], vertices))
    for (objective in c("shortest", "fastest")) {
      for (direction in directions) {
        if (is.function(progress_callback)) progress_callback(paste(mode, objective, direction))
        cursor <- cursor + 1L
        rows[[cursor]] <- route_one_direction(
          graph, origin, equipment, mode, objective, direction, k, radius_m,
          config$spatial$snap_warning_m, config$spatial$snap_max_m,
          speeds[[mode]] %||% 5, matches = matches
        )
      }
    }
  }
  dplyr::bind_rows(rows)
}

#' Calculate proximity under geometric and network metrics
#'
#' @param origins Valid origins with `origin_id`, `latitude` and `longitude`.
#' @param equipment Canonical equipment data.
#' @param graphs Named list of `dodgr` graphs (`foot`, `bicycle`, `motorcar`).
#' @param categories Optional category filter.
#' @param k Number of nearest neighbours retained for each metric.
#' @param radius_m Radius, in metres, whose members are also retained.
#' @param modes Requested network modes.
#' @param directions Network directions: origin-to-equipment, reverse, or both.
#' @param config Project configuration.
#' @param progress_callback Optional function receiving a routing stage description.
#' @return Long-form proximity result with one row per origin, equipment and metric.
#' @export
calculate_proximity <- function(origins, equipment, graphs = list(), categories = NULL,
                                k = NULL, radius_m = NULL,
                                modes = c("foot", "bicycle", "motorcar"),
                                directions = "origin_to_equipment",
                                config = read_sampa_config(), progress_callback = NULL) {
  # Resolved CEPs legitimately carry both provenance (CEP) and coordinates.
  # Validate the coordinate representation, keeping the original metadata.
  origins <- as.data.frame(origins)
  if ("origin_id" %in% names(origins) && !"query_id" %in% names(origins)) origins$query_id <- origins$origin_id
  origins$origin_id <- NULL
  original_cep <- origins$cep
  is_resolved <- "origin_method" %in% names(origins) && all(is.finite(origins$latitude) & is.finite(origins$longitude))
  validation_input <- origins
  if (is_resolved) validation_input$cep <- NA_character_
  checked <- validate_origins(validation_input, config)
  if (nrow(checked$errors)) {
    stop("Origens invalidas: ", paste(unique(checked$errors$message), collapse = "; "))
  }
  origins <- checked$valid
  if (is_resolved) origins$cep <- original_cep
  names(origins)[names(origins) == "query_id"] <- "origin_id"
  origins$origin_type <- ifelse(!is.na(origins$cep), "cep", "coordinates")
  validated <- validate_equipment(equipment, config)
  equipment <- validated$eligible
  if (length(setdiff(modes, c("foot", "bicycle", "motorcar")))) stop("Modo de rede desconhecido.")
  if (!is.null(categories) && length(categories)) {
    equipment <- equipment[equipment$category %in% categories, , drop = FALSE]
  }
  if (!nrow(equipment)) return(data.frame())
  if (!is.null(k) && (length(k) != 1 || !is.finite(k) || k != trunc(k) || k < 1L || k > 1000)) stop("k deve ser um inteiro entre 1 e 1000.")
  if (!is.null(radius_m) && (length(radius_m) != 1 || !is.finite(radius_m) || radius_m <= 0 || radius_m > 100000)) stop("radius_m deve estar entre 0 e 100000.")
  directions <- match.arg(directions, c("origin_to_equipment", "equipment_to_origin", "both"), several.ok = TRUE)
  if ("both" %in% directions) directions <- c("origin_to_equipment", "equipment_to_origin")

  all_rows <- lapply(seq_len(nrow(origins)), function(i) {
    origin <- origins[i, , drop = FALSE]
    k <- k %||% origin$k[[1]]
    radius_m <- radius_m %||% origin$radius_m[[1]]
    geometric <- geometric_rows(origin, equipment, k, radius_m, config$spatial$projected_crs)

    # Evaluate every eligible destination: fastest-path rankings cannot be
    # bounded safely by a geodesic top-k candidate envelope.
    routed <- network_rows(origin, equipment, graphs, modes, directions, k, radius_m, config,
      progress_callback)

    rows <- dplyr::bind_rows(geometric, routed)
    rows$selection_k <- k
    rows$selection_radius_m <- radius_m
    rows
  })
  results <- dplyr::bind_rows(all_rows)
  if (!nrow(results)) return(data.frame())
  diagnostics <- as.data.frame(table(results$origin_id, results$metric_id, results$routing_status), stringsAsFactors = FALSE)
  names(diagnostics) <- c("origin_id", "metric_id", "routing_status", "n")
  diagnostics <- diagnostics[diagnostics$n > 0, ]
  results <- results[results$selected %in% TRUE, , drop = FALSE]
  meta <- equipment[, intersect(c("equipment_id", "equipment_name", "category", "subcategory",
    "address", "district", "zone", "postal_code", "latitude", "longitude", "primary_group", "groups", "accessibility",
    "source_name", "snapshot_date", "within_municipality"), names(equipment)), drop = FALSE]
  results <- dplyr::left_join(results, meta, by = "equipment_id")
  origin_meta <- origins[, intersect(c("origin_id", "origin_type", "cep", "latitude", "longitude",
    "origin_quality_flag", "geocode_source", "geocode_precision", "geocoded_at"), names(origins)), drop = FALSE]
  names(origin_meta)[names(origin_meta) %in% c("cep", "latitude", "longitude")] <-
    paste0("origin_", names(origin_meta)[names(origin_meta) %in% c("cep", "latitude", "longitude")])
  results <- dplyr::left_join(results, origin_meta, by = "origin_id")
  attr(results, "routing_diagnostics") <- diagnostics
  attr(results, "missing_network_modes") <- setdiff(modes, names(graphs))
  results
}
