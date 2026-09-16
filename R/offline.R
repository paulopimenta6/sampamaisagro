#' Prepare local map context from IBGE and OpenStreetMap JSON
#' @param config Project configuration.
#' @param download Download missing raw map sources; FALSE never contacts services.
#' @return Network manifest, invisibly.
#' @export
prepare_offline_maps <- function(config = read_sampa_config(), download = TRUE) {
  ensure_project_dirs(config)
  raw <- file.path(config$data_dir, "osm")
  boundary <- file.path(raw, "sao-paulo-boundary.geojson")
  roads_file <- file.path(raw, "sao-paulo-roads.json")
  boundary_url <- "https://servicodados.ibge.gov.br/api/v3/malhas/municipios/3550308?formato=application/vnd.geo%2Bjson&qualidade=maxima"
  query <- "[out:json][timeout:240];way[highway](-24.07,-46.90,-23.30,-46.30);out geom;"
  roads_url <- paste0("https://overpass.private.coffee/api/interpreter?data=", utils::URLencode(query, reserved = TRUE))
  for (asset in list(list(path = boundary, url = boundary_url), list(path = roads_file, url = roads_url))) {
    if (!file.exists(asset$path)) {
      if (!download) stop("Camada local ausente: ", asset$path)
      message("Baixando ", basename(asset$path))
      req <- httr2::request(asset$url) |> httr2::req_user_agent(config$user_agent) |>
        httr2::req_timeout(300)
      temp <- paste0(asset$path, ".partial")
      httr2::req_perform(req, path = temp)
      if (!file.rename(temp, asset$path)) stop("Falha ao guardar ", asset$path)
    }
  }
  # Validate before replacing any working processed layers.
  sf::st_read(boundary, quiet = TRUE)
  message("Lendo vias locais OSM...")
  raw_data <- jsonlite::fromJSON(roads_file, simplifyVector = FALSE)
  if (!is.null(raw_data$remark)) stop("OSM retornou uma resposta incompleta: ", raw_data$remark)
  elements <- Filter(function(x) identical(x$type, "way") && length(x$geometry) >= 2 && !is.null(x$tags$highway), raw_data$elements)
  if (!length(elements)) stop("Nenhuma via OSM encontrada.")
  message("Convertendo ", length(elements), " vias para sf...")
  keys <- c("highway", "name", "oneway", "maxspeed", "access", "foot", "bicycle", "motor_vehicle", "surface", "junction")
  columns <- lapply(keys, function(k) vapply(elements,
    function(x) as.character(x$tags[[k]] %||% NA_character_), character(1)))
  attributes <- as.data.frame(stats::setNames(columns, keys), stringsAsFactors = FALSE)
  attributes$osm_id <- vapply(elements, function(x) as.character(x$id), character(1))
  geometry <- lapply(elements, function(x) sf::st_linestring(t(vapply(x$geometry,
    function(pt) c(pt$lon, pt$lat), numeric(2)))))
  lines <- sf::st_sf(attributes, geometry = sf::st_sfc(geometry, crs = 4326))
  lines <- lines[!duplicated(lines$osm_id), ]
  osm_timestamp <- raw_data$osm3s$timestamp_osm_base
  rm(raw_data, elements, geometry, attributes, columns)
  gc(verbose = FALSE)
  atomic_save_rds(lines, file.path(config$data_dir, "processed", "osm_lines.rds"))
  manifest <- list(created_at = utc_now(), source = "OpenStreetMap contributors / Overpass private.coffee",
    license = "ODbL 1.0", query = query, osm_timestamp = osm_timestamp,
    direction_access_policy = "v2: reversed -1; foot bidirectional; roundabouts; explicit no/private excluded; variable oneway excluded for vehicles",
    roads_sha256 = sha256_file(roads_file), boundary_sha256 = sha256_file(boundary),
    boundary_url = boundary_url, roads_url = roads_url, ways = nrow(lines),
    coverage = c(xmin = -46.90, ymin = -24.07, xmax = -46.30, ymax = -23.30),
    limitations = "Rede recortada; caminhos fora do recorte podem ser omitidos. Sem tr\u00e1fego real, restri\u00e7\u00f5es de convers\u00e3o ou auditoria de cal\u00e7adas. Snapping ao v\u00e9rtice mais pr\u00f3ximo com conectores retil\u00edneos estimados.")
  for (mode in config$network$modes) {
    message("Construindo grafo ", mode)
    graph <- build_network_graphs(lines, mode)[[mode]]
    attr(graph, "source_sha256") <- manifest$roads_sha256
    attr(graph, "coverage_bbox") <- manifest$coverage
    save_network_graphs(stats::setNames(list(graph), mode), config)
    manifest[[paste0(mode, "_edges")]] <- nrow(graph)
    rm(graph)
    gc(verbose = FALSE)
  }
  # Overview: main streets only; query points use complete source coordinates.
  major <- lines[lines$highway %in% c("motorway", "trunk", "primary", "secondary", "tertiary"), ]
  major <- sf::st_transform(sf::st_simplify(sf::st_transform(major, 31983), dTolerance = 15), 4326)
  atomic_save_rds(major[, "osm_id", drop = FALSE], file.path(config$data_dir, "processed", "map_roads.rds"))
  atomic_write_json(manifest, file.path(config$data_dir, "processed", "network_manifest.json"))
  invisible(manifest)
}
