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
  if (length(k) != 1L || !is.numeric(k) || !is.finite(k) || k < 1 || k != trunc(k)) {
    stop("k deve ser um inteiro positivo e finito.")
  }
  required <- c("origin_id", "equipment_id", "distance_m", "rank")
  for (data in list(a, b)) {
    if (length(setdiff(required, names(data)))) stop("Colunas ausentes para o pareamento de metricas.")
    for (field in intersect(c("origin_id", "equipment_id", "metric_id", "direction"), names(data))) {
      if (any(is.na(data[[field]]) | !nzchar(trimws(as.character(data[[field]]))))) {
        stop("Identificador ausente no pareamento: ", field)
      }
    }
    for (field in intersect(c("origin_id", "metric_id", "direction"), names(data))) {
      if (length(unique(data[[field]])) > 1L) stop("Cada conjunto deve conter um unico estrato de origem, metrica e sentido.")
    }
    if (anyDuplicated(data[c("origin_id", "equipment_id")])) {
      stop("Pareamento ambiguo: equipment_id duplicado no mesmo estrato.")
    }
  }
  if (nrow(a) && nrow(b) && as.character(a$origin_id[[1]]) != as.character(b$origin_id[[1]])) {
    stop("A e B devem pertencer a mesma origem.")
  }
  merged <- merge(
    a[, required, drop = FALSE], b[, required, drop = FALSE],
    by = c("origin_id", "equipment_id"), suffixes = c("_a", "_b")
  )
  n_a <- length(unique(a$equipment_id))
  n_b <- length(unique(b$equipment_id))
  valid_rank <- function(x) is.finite(x) & x > 0
  rank_ok <- valid_rank(merged$rank_a) & valid_rank(merged$rank_b)
  ranks_a <- merged$rank_a[rank_ok]
  ranks_b <- merged$rank_b[rank_ok]
  can_correlate <- length(ranks_a) >= 2L && length(unique(ranks_a)) > 1L && length(unique(ranks_b)) > 1L
  # Top-k sets use all available rows, independently of the paired intersection.
  top_a <- unique(a$equipment_id[valid_rank(a$rank) & a$rank <= k])
  top_b <- unique(b$equipment_id[valid_rank(b$rank) & b$rank <= k])
  union_top <- union(top_a, top_b)
  distance_ok <- is.finite(merged$distance_m_a) & is.finite(merged$distance_m_b)
  difference_m <- merged$distance_m_a[distance_ok] - merged$distance_m_b[distance_ok]
  n_distance <- length(difference_m)
  difference_quantiles <- if (n_distance) {
    stats::quantile(difference_m, c(0.25, 0.5, 0.75), names = FALSE, type = 7)
  } else rep(NA_real_, 3L)
  mean_difference <- if (n_distance) mean(difference_m) else NA_real_
  sd_difference <- if (n_distance >= 2L) stats::sd(difference_m) else NA_real_
  data.frame(
    n_a = n_a, n_b = n_b, n_common = nrow(merged),
    common_pct_a = if (n_a) 100 * nrow(merged) / n_a else NA_real_,
    common_pct_b = if (n_b) 100 * nrow(merged) / n_b else NA_real_,
    n_rank_common = length(ranks_a),
    # Fastest paths are ranked by duration, not by their travelled distance.
    spearman_rho = if (can_correlate) stats::cor(ranks_a, ranks_b, method = "spearman") else NA_real_,
    kendall_tau = if (can_correlate) stats::cor(ranks_a, ranks_b, method = "kendall") else NA_real_,
    top_k_jaccard = if (length(union_top)) length(intersect(top_a, top_b)) / length(union_top) else NA_real_,
    k = k, n_distance_common = n_distance,
    mean_difference_m = mean_difference, median_difference_m = difference_quantiles[2],
    p25_difference_m = difference_quantiles[1], p75_difference_m = difference_quantiles[3],
    iqr_difference_m = difference_quantiles[3] - difference_quantiles[1], sd_difference_m = sd_difference,
    limits_lower_m = if (n_distance >= 2L) mean_difference - 1.96 * sd_difference else NA_real_,
    limits_upper_m = if (n_distance >= 2L) mean_difference + 1.96 * sd_difference else NA_real_
  )
}

#' Compare distance metrics without treating one as a gold standard
#'
#' Separates three questions: preservation of ordering (Spearman/Kendall),
#' overlap of top-k selections (Jaccard), and paired differences in metres.
#' High rank correlations do not imply small absolute distance differences.
#'
#' All pairing uses exactly `origin_id + equipment_id`, within one origin and
#' one metric/direction on each side. Duplicate equipment within an origin,
#' metric and direction cause an error rather than a Cartesian join. Identifiers
#' must be present and nonblank. Metric identifiers and directions are returned
#' separately as `metric_a`, `direction_a`, `metric_b` and `direction_b`.
#'
#' `n_a` and `n_b` count distinct equipment available in the supplied sets;
#' `n_common` counts their intersection, regardless of missing ranks/distances.
#' `common_pct_a` and `common_pct_b` divide this intersection by the respective
#' set size, returning `NA` for a zero denominator. An origin observed on either
#' side is included; an absent set has size zero. This describes availability in
#' the retained input, not unobserved equipment or pre-selection routing failures.
#'
#' `n_rank_common` counts common pairs with finite, positive ranks on both sides.
#' Spearman and Kendall use those existing ranks, with ties preserved. They are
#' `NA` with fewer than two such pairs or a constant rank vector; no p-values are
#' calculated. For `fastest` network paths, ranks were determined by modeled time:
#' these correlations compare orderings by time, not distance correlations.
#'
#' Top-k sets contain equipment with finite, positive `rank <= k`, independently
#' of the paired intersection. Jaccard is intersection size divided by union
#' size: disjoint nonempty selections give zero, identical nonempty selections
#' give one, and two empty selections give `NA`. The requested `k` is returned.
#'
#' `difference_m = distance_m_a - distance_m_b`, explicitly A minus B. Only common
#' pairs with both distances finite enter `n_distance_common` and the mean,
#' median, P25, P75, IQR (P75 minus P25), and sample SD of differences. Quantiles
#' use type 7. No valid pair gives `NA` for all difference summaries. One valid
#' pair can be summarized, but SD and limits remain `NA`. For `fastest`, these
#' differences compare lengths of routes chosen by modeled time, without reranking.
#'
#' Limits are mean difference plus/minus 1.96 sample SD only with at least two
#' valid distance pairs. They are descriptive Bland-Altman summaries, not
#' confidence intervals or evidence of agreement. Interpretation depends on the
#' distribution of differences; heteroscedasticity and spatial dependence may
#' compromise it. Metrics are distinct operational definitions, not a gold
#' standard. No formal Bland-Altman test or causal inference is performed.
#' Before generating pairs, distinct metric/direction combinations are sorted
#' canonically by character `metric_id`, then `direction`, using radix ordering.
#' A precedes B in that order, independently of the data frame's row order.
#' Signed differences always use A minus B, so their sign is reproducible for
#' the same data. A and B label only the calculation's orientation, without
#' privileging either metric. Explicit calls to `metric_pair_agreement(a, b, k)`
#' retain the caller's argument order; deliberately reversing them reverses the
#' signed differences.
#'
#' @param results Retained long-form results from `calculate_proximity()`, with
#'   `origin_id`, `equipment_id`, `metric_id`, `direction`, numeric `distance_m`
#'   and numeric `rank`. Empty input returns a zero-row table with the same schema.
#' @param k Positive integer cut-off used for top-k set overlap.
#' @return A data frame with origin and separate metric/direction identifiers,
#'   availability and common-pair counts, coverage percentages, rank correlations,
#'   top-k Jaccard and `k`, valid distance-pair count, signed difference summaries
#'   in metres, and descriptive lower/upper limits in metres.
#' @md
#' @export
metric_agreement <- function(results, k = 10L) {
  empty_pairs <- data.frame(origin_id = character(), equipment_id = character(),
    distance_m = numeric(), rank = numeric())
  empty <- cbind(data.frame(origin_id = character(), metric_a = character(), direction_a = character(),
    metric_b = character(), direction_b = character()), metric_pair_agreement(empty_pairs, empty_pairs, k)[0, ])
  if (!nrow(results)) return(empty)
  required <- c("origin_id", "equipment_id", "metric_id", "direction", "distance_m", "rank")
  if (length(setdiff(required, names(results)))) stop("Resultado nao possui as colunas de concordancia.")
  identifiers <- c("origin_id", "metric_id", "direction", "equipment_id")
  for (field in identifiers) {
    if (any(is.na(results[[field]]) | !nzchar(trimws(as.character(results[[field]]))))) {
      stop("Identificador ausente na comparacao: ", field)
    }
  }
  if (anyDuplicated(results[identifiers])) {
    stop("Pareamento ambiguo: equipment_id duplicado em origin_id + metric_id + direction.")
  }
  metrics <- unique(results[c("metric_id", "direction")])
  metrics <- metrics[order(as.character(metrics$metric_id), as.character(metrics$direction),
    method = "radix"), , drop = FALSE]
  if (nrow(metrics) < 2L) return(empty)
  pairs <- utils::combn(seq_len(nrow(metrics)), 2L, simplify = FALSE)
  dplyr::bind_rows(lapply(pairs, function(pair) {
    a <- results[results$metric_id == metrics$metric_id[pair[1]] &
      results$direction == metrics$direction[pair[1]], , drop = FALSE]
    b <- results[results$metric_id == metrics$metric_id[pair[2]] &
      results$direction == metrics$direction[pair[2]], , drop = FALSE]
    origin_ids <- union(unique(a$origin_id), unique(b$origin_id))
    dplyr::bind_rows(lapply(origin_ids, function(origin_id) {
      stats_row <- metric_pair_agreement(
        a[a$origin_id == origin_id, , drop = FALSE],
        b[b$origin_id == origin_id, , drop = FALSE], k
      )
      stats_row$origin_id <- origin_id
      stats_row$metric_a <- as.character(metrics$metric_id[pair[1]])
      stats_row$direction_a <- as.character(metrics$direction[pair[1]])
      stats_row$metric_b <- as.character(metrics$metric_id[pair[2]])
      stats_row$direction_b <- as.character(metrics$direction[pair[2]])
      columns <- c("origin_id", "metric_a", "direction_a", "metric_b", "direction_b")
      stats_row[, c(columns, setdiff(names(stats_row), columns))]
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
