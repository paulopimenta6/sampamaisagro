load_map_context <- function(config = read_sampa_config()) {
  path <- file.path(config$data_dir, "osm", "sao-paulo-boundary.geojson")
  boundary <- if (file.exists(path)) sf::st_read(path, quiet = TRUE) else NULL
  roads_path <- file.path(config$data_dir, "processed", "map_roads.rds")
  roads <- if (file.exists(roads_path)) readRDS(roads_path) else NULL
  # Encode once: Leaflet's nested sf conversion is very slow for 50,000 ways.
  # A single GeoJSON feature also avoids creating 50,000 browser DOM elements.
  # This visual encoding does not modify any routing graph.
  roads_geojson <- if (!is.null(roads) && nrow(roads)) as.character(jsonlite::toJSON(
    list(type = "Feature", properties = list(name = "Vias OSM"), geometry = list(
      type = "MultiLineString", coordinates = unname(lapply(sf::st_geometry(roads), unclass)))),
    auto_unbox = TRUE, digits = 7)) else NULL
  list(boundary = boundary, roads_geojson = roads_geojson)
}

make_leaflet_map <- function(results, origins = NULL, metric_id = NULL,
                             equipment = NULL, context = list(), radius_m = NULL) {
  map <- leaflet::leaflet(options = leaflet::leafletOptions(preferCanvas = FALSE, minZoom = 8)) |>
    leaflet::addScaleBar(position = "bottomleft") |>
    leaflet::setView(lng = -46.65, lat = -23.65, zoom = 10)
  # All layers are local vectors. No remote tiles, fonts, geocoder or route API.
  if (!is.null(context$boundary)) map <- leaflet::addPolygons(map, data = context$boundary,
    color = "#597967", weight = 2, fillColor = "#e7efe7", fillOpacity = 0.6,
    group = "Limite municipal", label = "S\u00e3o Paulo \u00b7 malha simplificada IBGE")
  if (!is.null(context$roads_geojson)) map <- leaflet::addGeoJSON(map,
    geojson = context$roads_geojson, color = "#b5c2b7", weight = 1, opacity = 0.8, group = "Vias OSM",
    options = leaflet::pathOptions(interactive = FALSE))
  query <- nrow(results) > 0
  if (query) {
    metric_id <- metric_id %||% unique(results$metric_id)[1]
    shown <- results[results$metric_id == metric_id & is.finite(results$distance_m), , drop = FALSE]
    shown <- shown[!duplicated(paste(shown$origin_id, shown$equipment_id, shown$direction)), ]
  } else shown <- equipment
  if (!is.null(shown) && nrow(shown)) {
    shown <- shown[is.finite(shown$longitude) & is.finite(shown$latitude), , drop = FALSE]
    group <- if ("primary_group" %in% names(shown)) shown$primary_group else shown$category
    pal <- leaflet::colorFactor(grDevices::hcl.colors(12, "Dark 3"), domain = sort(unique(group)))
    popup <- lapply(seq_len(nrow(shown)), function(i) htmltools::HTML(paste0(
      "<strong>", htmltools::htmlEscape(shown$equipment_name[i]), "</strong><br>",
      htmltools::htmlEscape(group[i]), "<br>",
      htmltools::htmlEscape(shown$address[i] %||% "Endere\u00e7o n\u00e3o informado"),
      if (query) sprintf("<br>Dist\u00e2ncia: %.0f m \u00b7 posi\u00e7\u00e3o: %s<br>%s",
        shown$distance_m[i], shown$rank[i], htmltools::htmlEscape(shown$metric_label[i])) else "",
      if ("accessibility" %in% names(shown)) paste0("<br>Acessibilidade: ",
        htmltools::htmlEscape(shown$accessibility[i])) else "")))
    map <- leaflet::addCircleMarkers(map, lng = shown$longitude, lat = shown$latitude,
      radius = if (query) 6 else 4, color = pal(group), stroke = TRUE, weight = 1,
      fillOpacity = 0.85, popup = popup, label = shown$equipment_name, group = "Equipamentos") |>
      leaflet::addLegend("bottomright", pal = pal, values = group, title = "Equipamentos")
    coords <- shown[, c("longitude", "latitude"), drop = FALSE]
    if (!is.null(origins) && nrow(origins)) coords <- rbind(coords, origins[, names(coords), drop = FALSE])
    bounds <- c(range(coords$longitude), range(coords$latitude))
    if (diff(bounds[1:2]) > 0 && diff(bounds[3:4]) > 0) map <- leaflet::fitBounds(map,
      bounds[1], bounds[3], bounds[2], bounds[4])
  }
  if (!is.null(origins) && nrow(origins)) {
    labels <- origins$origin_id %||% origins$query_id
    if (!is.null(radius_m)) map <- leaflet::addCircles(map, lng = origins$longitude,
      lat = origins$latitude, radius = radius_m, color = "#b96b24", weight = 1,
      fillOpacity = 0.03, group = "Raio geod\u00e9sico (refer\u00eancia)")
    map <- leaflet::addCircleMarkers(map, lng = origins$longitude, lat = origins$latitude,
      radius = 9, color = "#172f57", fillColor = "#ffffff", fillOpacity = 1, weight = 4,
      label = paste("Origem:", labels), group = "Origens")
  }
  map <- leaflet::addLayersControl(map,
    overlayGroups = c("Equipamentos", "Origens", "Raio geod\u00e9sico (refer\u00eancia)", "Vias OSM", "Limite municipal"),
    options = leaflet::layersControlOptions(collapsed = TRUE))
  leaflet::addControl(map, html = paste(
    "Mapa offline \u00b7 pontos, n\u00e3o tra\u00e7ados de rotas.<br>",
    "Fontes: Prefeitura/Sampa+Rural \u00b7 IBGE \u00b7 \u00a9 OpenStreetMap contributors (ODbL)."),
    position = "topleft")
}

make_static_map <- function(results, metric_id = NULL, context = list()) {
  metric_id <- metric_id %||% unique(results$metric_id)[1]
  shown <- results[results$metric_id == metric_id & is.finite(results$distance_m), , drop = FALSE]
  p <- ggplot2::ggplot()
  if (!is.null(context$boundary)) p <- p + ggplot2::geom_sf(data = context$boundary,
    fill = "#edf3eb", colour = "#96ab99", linewidth = 0.4)
  if (nrow(shown)) {
    points <- sf::st_as_sf(shown, coords = c("longitude", "latitude"), crs = 4326)
    p <- p + ggplot2::geom_sf(data = points, ggplot2::aes(colour = distance_m), size = 2)
    if (all(c("origin_longitude", "origin_latitude") %in% names(shown))) {
      origins <- unique(shown[, c("origin_longitude", "origin_latitude")])
      origins <- sf::st_as_sf(origins, coords = c("origin_longitude", "origin_latitude"), crs = 4326)
      p <- p + ggplot2::geom_sf(data = origins, shape = 4, colour = "#13325b", size = 4)
    }
    xx <- range(c(shown$longitude, shown$origin_longitude), na.rm = TRUE) + c(-0.005, 0.005)
    yy <- range(c(shown$latitude, shown$origin_latitude), na.rm = TRUE) + c(-0.005, 0.005)
    p <- p + ggplot2::coord_sf(xlim = xx, ylim = yy, expand = FALSE)
  }
  p + ggplot2::scale_colour_viridis_c(name = "Dist\u00e2ncia (m)") +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::labs(title = "Equipamentos pr\u00f3ximos \u00b7 mapa offline",
      subtitle = if (nrow(shown)) unique(shown$metric_label)[1] else "Nenhum equipamento selecionado",
      caption = "Pontos: Sampa+Rural | Limite: IBGE\nCruz: origem aproximada; n\u00e3o representa domic\u00edlio",
      x = "Longitude", y = "Latitude")
}

#' Create an interactive proximity map
#' @param results Long-form proximity results.
#' @param origins Optional resolved origins.
#' @param metric_id Metric to display.
#' @return A Leaflet HTML widget.
#' @export
create_interactive_map <- function(results, origins = NULL, metric_id = NULL) {
  make_leaflet_map(results, origins, metric_id, context = load_map_context())
}

#' Create a publication-oriented static proximity map
#' @param results Long-form proximity results.
#' @param metric_id Metric to display.
#' @return A ggplot object.
#' @export
create_static_map <- function(results, metric_id = NULL) {
  make_static_map(results, metric_id, context = load_map_context())
}
