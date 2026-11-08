#' Summarize retained proximity pairs by origin, metric and direction
#'
#' All counts describe the rows supplied in each `origin_id`, `metric_id` and
#' `direction` stratum. Distance summaries use only finite `distance_m` values,
#' with quantiles of type 7 and IQR equal to P75 minus P25. Without a finite
#' distance, every distance summary is `NA`. Missing radius flags are not counted
#' as inside the radius; `no_raio` depends exclusively on `within_radius`.
#'
#' `calculate_proximity()` retains pairs inside the radius OR in the selected
#' top-k. If the supplied table has been further restricted to top-k, it need not
#' contain every equipment inside the radius. This function does not infer pairs
#' discarded before selection; network failures belong to routing diagnostics.
#'
#' These are descriptions of selected pairs, not automatically the accessibility
#' distribution of Sao Paulo's population. Repeated rows across metrics are not
#' independent observations. Interpret each metric by its operational definition.
#' For `fastest` network paths, ranking uses modeled time, while `distance_m`
#' remains the length of the selected path. Origins, metrics and directions are
#' never pooled here.
#'
#' @param results Long-form retained proximity results. Requires `origin_id`,
#'   `metric_id`, `direction`, `equipment_id`, `distance_m` and `within_radius`.
#'   The optional presentation column `metric_label` defaults to `metric_id`.
#' @return A data frame with one row per stratum, retained/finite/nonfinite pair
#'   counts, distinct equipment, radius counts and distance summaries in metres.
#'   Empty input returns zero rows with the same columns and types.
#' @examples
#' \dontrun{
#' equipment <- load_equipment_data()
#' list_equipment_groups(equipment)
#' origins <- resolve_origins(data.frame(latitude = -23.55, longitude = -46.63))
#' results <- calculate_proximity(origins$valid, equipment, modes = character())
#' proximity_summary(results)
#' create_static_map(results)
#' render_proximity_report(results, "relatorio.html", origins$valid, equipment)
#' }
#' @export
proximity_summary <- function(results) {
  if (!nrow(results)) return(data.frame(
    origin_id = character(), metric_id = character(), direction = character(), metric_label = character(),
    pares_retidos = integer(), pares_distancia_valida = integer(), pares_distancia_ausente = integer(),
    equipamentos = integer(), no_raio = integer(), minimo_m = numeric(), p25_m = numeric(),
    mediana_m = numeric(), p75_m = numeric(), iqr_m = numeric(), p90_m = numeric(), maximo_m = numeric()))
  required <- c("origin_id", "metric_id", "direction", "equipment_id", "distance_m", "within_radius")
  missing_columns <- setdiff(required, names(results))
  if (length(missing_columns)) stop("Colunas obrigatorias ausentes: ", paste(missing_columns, collapse = ", "))
  if (!"metric_label" %in% names(results)) results$metric_label <- results$metric_id
  grouped <- dplyr::group_by(results,
    dplyr::across(dplyr::all_of(c("origin_id", "metric_id", "direction"))))
  summary <- dplyr::group_modify(grouped, function(data, key) {
    distances <- data$distance_m[is.finite(data$distance_m)]
    quantiles <- if (length(distances)) {
      stats::quantile(distances, c(0, 0.25, 0.5, 0.75, 0.9, 1), names = FALSE, type = 7)
    } else rep(NA_real_, 6L)
    data.frame(metric_label = as.character(data$metric_label[[1]]),
      pares_retidos = nrow(data), pares_distancia_valida = length(distances),
      pares_distancia_ausente = nrow(data) - length(distances),
      equipamentos = dplyr::n_distinct(data$equipment_id), no_raio = sum(data$within_radius %in% TRUE),
      minimo_m = quantiles[1], p25_m = quantiles[2], mediana_m = quantiles[3],
      p75_m = quantiles[4], iqr_m = quantiles[4] - quantiles[2],
      p90_m = quantiles[5], maximo_m = quantiles[6], stringsAsFactors = FALSE)
  })
  as.data.frame(dplyr::ungroup(summary))
}

#' Aggregate equipment into a regular hexagonal grid
#'
#' @param equipment Canonical equipment data.
#' @param cell_size_m Approximate centre-to-centre cell size in metres.
#' @param boundary Optional `sf` polygon limiting the grid.
#' @param projected_crs Metric CRS used for tessellation.
#' @return An `sf` object with counts and density per square kilometre.
#' @export
create_hex_grid <- function(equipment, cell_size_m = 2000, boundary = NULL, projected_crs = 31983) {
  valid <- equipment[is.finite(equipment$longitude) & is.finite(equipment$latitude), , drop = FALSE]
  if (!nrow(valid)) stop("Nao ha equipamentos com coordenadas validas.")
  pts <- sf::st_as_sf(valid, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)
  pts_m <- sf::st_transform(pts, projected_crs)
  if (is.null(boundary)) {
    boundary_m <- sf::st_as_sfc(sf::st_bbox(pts_m))
    boundary_m <- sf::st_buffer(boundary_m, cell_size_m)
  } else {
    boundary_m <- sf::st_transform(sf::st_make_valid(boundary), projected_crs)
  }
  cells <- sf::st_make_grid(boundary_m, cellsize = cell_size_m, square = FALSE)
  cells <- sf::st_sf(hex_id = sprintf("h%05d", seq_along(cells)), geometry = cells)
  cells <- suppressWarnings(sf::st_intersection(cells, sf::st_union(boundary_m)))
  cells <- suppressWarnings(sf::st_collection_extract(cells, "POLYGON"))
  cells <- cells[as.numeric(sf::st_area(cells)) > 0, , drop = FALSE]
  joined <- sf::st_join(pts_m, cells, join = sf::st_within, left = TRUE)
  counts <- as.data.frame(table(joined$hex_id), stringsAsFactors = FALSE)
  names(counts) <- c("hex_id", "equipment_n")
  cells <- dplyr::left_join(cells, counts, by = "hex_id")
  cells$equipment_n[is.na(cells$equipment_n)] <- 0L
  cells$area_km2 <- as.numeric(sf::st_area(cells)) / 1e6
  cells$density_km2 <- cells$equipment_n / cells$area_km2
  sf::st_transform(cells, 4326)
}

metric_pair_agreement <- function(a, b, k) {
  merged <- merge(
    a[, c("origin_id", "equipment_id", "distance_m", "rank")],
    b[, c("origin_id", "equipment_id", "distance_m", "rank")],
    by = c("origin_id", "equipment_id"), suffixes = c("_a", "_b")
  )
  if (!nrow(merged)) {
    return(data.frame(n_common = 0L, spearman_rho = NA_real_, kendall_tau = NA_real_,
      mean_difference_m = NA_real_, limits_lower_m = NA_real_, limits_upper_m = NA_real_,
      top_k_jaccard = NA_real_))
  }
  dif <- merged$distance_m_a - merged$distance_m_b
  top_a <- unique(a$equipment_id[a$rank <= k & !is.na(a$rank)])
  top_b <- unique(b$equipment_id[b$rank <= k & !is.na(b$rank)])
  union_top <- union(top_a, top_b)
  data.frame(
    n_common = nrow(merged),
    # Fastest paths are ranked by duration, not by their travelled distance.
    spearman_rho = suppressWarnings(stats::cor(merged$rank_a, merged$rank_b,
      method = "spearman", use = "complete.obs")),
    kendall_tau = suppressWarnings(stats::cor(merged$rank_a, merged$rank_b,
      method = "kendall", use = "complete.obs")),
    mean_difference_m = mean(dif, na.rm = TRUE),
    limits_lower_m = mean(dif, na.rm = TRUE) - 1.96 * stats::sd(dif, na.rm = TRUE),
    limits_upper_m = mean(dif, na.rm = TRUE) + 1.96 * stats::sd(dif, na.rm = TRUE),
    top_k_jaccard = if (length(union_top)) length(intersect(top_a, top_b)) / length(union_top) else NA_real_
  )
}

#' Compare distance metrics without treating one as a gold standard
#'
#' @param results Long-form result returned by `calculate_proximity()`.
#' @param k Cut-off used for top-k set agreement.
#' @return Pairwise rank correlations, Bland-Altman summaries and Jaccard overlap.
#' @export
metric_agreement <- function(results, k = 10L) {
  required <- c("origin_id", "equipment_id", "metric_id", "distance_m", "rank")
  if (length(setdiff(required, names(results)))) stop("Resultado nao possui as colunas de concordancia.")
  metric_keys <- unique(paste(results$metric_id, results$direction, sep = "|"))
  if (length(metric_keys) < 2L) return(data.frame())
  pairs <- utils::combn(metric_keys, 2L, simplify = FALSE)
  dplyr::bind_rows(lapply(pairs, function(pair) {
    key <- paste(results$metric_id, results$direction, sep = "|")
    a <- results[key == pair[1], , drop = FALSE]
    b <- results[key == pair[2], , drop = FALSE]
    origin_ids <- intersect(unique(a$origin_id), unique(b$origin_id))
    dplyr::bind_rows(lapply(origin_ids, function(origin_id) {
      stats_row <- metric_pair_agreement(
        a[a$origin_id == origin_id, , drop = FALSE],
        b[b$origin_id == origin_id, , drop = FALSE], k
      )
      stats_row$origin_id <- origin_id
      stats_row$metric_a <- pair[1]
      stats_row$metric_b <- pair[2]
      stats_row[, c("origin_id", "metric_a", "metric_b",
        setdiff(names(stats_row), c("origin_id", "metric_a", "metric_b")))]
    }))
  }))
}

#' Fit an exploratory spatial count model
#'
#' @param grid An `sf` grid with a non-negative count column.
#' @param count_col Name of count outcome.
#' @param predictors Optional numeric predictor names.
#' @return List with Poisson and negative-binomial fits, chosen model and diagnostics.
#' @export
fit_spatial_count_model <- function(grid, count_col = "equipment_n", predictors = character()) {
  if (!inherits(grid, "sf")) stop("grid deve ser um objeto sf.")
  if (!count_col %in% names(grid)) stop("Coluna de contagem ausente: ", count_col)
  analysis <- sf::st_drop_geometry(grid)
  analysis$.count <- as.numeric(analysis[[count_col]])
  analysis$.area_km2 <- if ("area_km2" %in% names(analysis)) analysis$area_km2 else
    as.numeric(sf::st_area(sf::st_transform(grid, 31983))) / 1e6
  analysis$.area_km2 <- pmax(analysis$.area_km2, .Machine$double.eps)
  predictors <- intersect(predictors, names(analysis))
  rhs <- if (length(predictors)) paste(predictors, collapse = " + ") else "1"
  formula <- stats::as.formula(paste(".count ~", rhs, "+ offset(log(.area_km2))"))
  model_warnings <- character()
  capture_model_warnings <- function(expr) withCallingHandlers(expr, warning = function(w) {
    model_warnings <<- unique(c(model_warnings, conditionMessage(w)))
    invokeRestart("muffleWarning")
  })
  poisson <- capture_model_warnings(stats::glm(formula, data = analysis, family = stats::poisson()))
  dispersion <- sum(stats::residuals(poisson, type = "pearson")^2) / poisson$df.residual
  negbin <- if (requireNamespace("MASS", quietly = TRUE)) {
    tryCatch(capture_model_warnings(MASS::glm.nb(formula, data = analysis)), error = function(e) NULL)
  } else NULL
  chosen <- if (!is.null(negbin) && is.finite(dispersion) && dispersion > 1.5) negbin else poisson

  moran <- NULL
  if (requireNamespace("spdep", quietly = TRUE) && nrow(grid) > 3L) {
    neighbours <- tryCatch(spdep::poly2nb(grid, queen = TRUE), error = function(e) NULL)
    weights <- if (is.null(neighbours)) NULL else
      tryCatch(spdep::nb2listw(neighbours, style = "W", zero.policy = TRUE), error = function(e) NULL)
    if (!is.null(weights)) {
      moran <- tryCatch(spdep::moran.test(stats::residuals(chosen, type = "pearson"), weights,
        zero.policy = TRUE), error = function(e) NULL)
    }
  }
  list(
    poisson = poisson, negative_binomial = negbin, model = chosen,
    selected_family = if (identical(chosen, negbin) && !is.null(negbin)) "negative_binomial" else "poisson",
    dispersion = dispersion, moran = moran, warnings = model_warnings,
    caveat = "Modelo exploratorio associacional; nao sustenta inferencia causal sem desenho identificador."
  )
}
