metric_palette <- function(values) {
  leaflet::colorBin("viridis", domain = values, bins = 5, pretty = TRUE, na.color = "#9e9e9e")
}

make_leaflet_map <- function(results, origins = NULL, metric_id = NULL) {
  if (!nrow(results)) return(leaflet::leaflet() |> leaflet::addTiles())
  metric_id <- metric_id %||% unique(results$metric_id)[1]
  shown <- results[results$metric_id == metric_id & is.finite(results$distance_m), , drop = FALSE]
  pal <- metric_palette(shown$distance_m)
  labels <- htmltools::HTML(sprintf(
    "<strong>%s</strong><br/>Categoria: %s<br/>Distancia: %.0f m<br/>Posicao: %s",
    htmltools::htmlEscape(shown$equipment_name), htmltools::htmlEscape(shown$category),
    shown$distance_m, shown$rank
  ))
  map <- leaflet::leaflet(shown) |>
    leaflet::addProviderTiles("CartoDB.Positron", options = leaflet::providerTileOptions(noWrap = TRUE)) |>
    leaflet::addCircleMarkers(
      lng = ~longitude, lat = ~latitude, radius = 6, stroke = TRUE, weight = 1,
      color = ~pal(distance_m), fillOpacity = 0.85, label = labels, group = "Equipamentos"
    ) |>
    leaflet::addLegend("bottomright", pal = pal, values = ~distance_m,
      title = "Distancia (m)", opacity = 0.9)
  if (!is.null(origins) && nrow(origins)) {
    map <- map |> leaflet::addAwesomeMarkers(
      data = origins, lng = ~longitude, lat = ~latitude,
      icon = leaflet::makeAwesomeIcon(icon = "home", markerColor = "blue", library = "fa"),
      label = ~origin_id, group = "Origens"
    )
  }
  map |> leaflet::addLayersControl(overlayGroups = c("Origens", "Equipamentos"),
    options = leaflet::layersControlOptions(collapsed = FALSE))
}

make_static_map <- function(results, metric_id = NULL) {
  metric_id <- metric_id %||% unique(results$metric_id)[1]
  shown <- results[results$metric_id == metric_id & is.finite(results$distance_m), , drop = FALSE]
  ggplot2::ggplot(shown, ggplot2::aes(longitude, latitude, colour = distance_m)) +
    ggplot2::geom_point(size = 2.5, alpha = 0.85) +
    ggplot2::scale_colour_viridis_c(name = "Distancia (m)") +
    ggplot2::coord_equal() +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::labs(title = unique(shown$metric_label)[1], x = "Longitude", y = "Latitude")
}

#' Create an interactive proximity map
#'
#' @param results Long-form proximity results.
#' @param origins Optional resolved origins.
#' @param metric_id Metric to display; defaults to the first one.
#' @return A Leaflet HTML widget.
#' @export
create_interactive_map <- function(results, origins = NULL, metric_id = NULL) {
  make_leaflet_map(results, origins, metric_id)
}

#' Create a publication-oriented static proximity map
#'
#' @param results Long-form proximity results.
#' @param metric_id Metric to display; defaults to the first one.
#' @return A `ggplot2` object.
#' @export
create_static_map <- function(results, metric_id = NULL) {
  make_static_map(results, metric_id)
}
