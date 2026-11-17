agreement_rows <- function(ids, ranks = seq_along(ids), distances = seq_along(ids) * 100,
                           metric = "A", direction = "symmetric", origin = "o1") {
  data.frame(origin_id = rep(origin, length(ids)), equipment_id = ids,
    metric_id = rep(metric, length(ids)), direction = rep(direction, length(ids)),
    distance_m = distances, rank = ranks, stringsAsFactors = FALSE)
}

test_that("identical ranks and top-k sets do not imply small distance differences", {
  a <- agreement_rows(letters[1:3])
  b <- agreement_rows(letters[1:3], distances = c(200, 400, 600), metric = "B")
  result <- metric_agreement(rbind(a, b), k = 2L)
  expect_equal(result$spearman_rho, 1)
  expect_equal(result$kendall_tau, 1)
  expect_equal(result$top_k_jaccard, 1)
  expect_equal(result$n_rank_common, 3L)
  expect_equal(result$mean_difference_m, -200)
  expect_equal(result$k, 2L)
  expect_false(any(grepl("p_value|p.value|pvalue", names(result))))
})

test_that("inverted ranks give negative correlations and disjoint top-1 selections", {
  a <- agreement_rows(letters[1:3])
  b <- agreement_rows(letters[1:3], ranks = 3:1, metric = "B")
  result <- metric_pair_agreement(a, b, k = 1L)
  expect_equal(result$spearman_rho, -1)
  expect_equal(result$kendall_tau, -1)
  expect_equal(result$top_k_jaccard, 0)
  expect_equal(result$mean_difference_m, 0)
})

test_that("partial top-k overlap includes equipment present on only one side", {
  a <- agreement_rows(c("a", "b", "c"), distances = c(100, 200, 300))
  b <- agreement_rows(c("b", "c", "d"), distances = c(150, 250, 999), metric = "B")
  result <- metric_pair_agreement(a, b, k = 2L)
  # A_k = {a,b}, B_k = {b,c}; union = {a,b,c}, intersection = {b}.
  expect_equal(result$top_k_jaccard, 1 / 3)
  expect_equal(result$n_common, 2L)
  expect_equal(result$n_distance_common, 2L)
  expect_equal(result$mean_difference_m, 50)
})

test_that("nonempty disjoint sets have Jaccard zero without any paired equipment", {
  a <- agreement_rows(c("a", "b"))
  b <- agreement_rows(c("c", "d"), metric = "B")
  expect_warning(result <- metric_agreement(rbind(a, b), k = 2L), NA)
  expect_equal(result$n_a, 2L)
  expect_equal(result$n_b, 2L)
  expect_equal(result$n_common, 0L)
  expect_equal(result$common_pct_a, 0)
  expect_equal(result$common_pct_b, 0)
  expect_equal(result$top_k_jaccard, 0)
  expect_true(is.na(result$spearman_rho))
  expect_true(is.na(result$kendall_tau))
  expect_true(is.na(result$median_difference_m))
})

test_that("two empty top-k selections return NA and a single empty selection returns zero", {
  a <- agreement_rows(letters[1:2], ranks = 3:4)
  b <- agreement_rows(letters[1:2], ranks = 3:4, metric = "B")
  expect_true(is.na(metric_pair_agreement(a, b, k = 2L)$top_k_jaccard))
  a$rank <- 1:2
  expect_equal(metric_pair_agreement(a, b, k = 2L)$top_k_jaccard, 0)
  a$rank <- c(NA, Inf)
  b$rank <- c(NaN, -Inf)
  expect_warning(result <- metric_pair_agreement(a, b, k = 2L), NA)
  expect_true(is.na(result$top_k_jaccard))
  expect_equal(result$n_rank_common, 0L)
})

test_that("coverage uses distinct available equipment rather than valid paired ranks", {
  a <- agreement_rows(c("a", "b", "c", "d"))
  b <- agreement_rows(c("c", "d", "e"), metric = "B")
  result <- metric_pair_agreement(a, b, k = 2L)
  expect_equal(result$n_a, 4L)
  expect_equal(result$n_b, 3L)
  expect_equal(result$n_common, 2L)
  expect_equal(result$common_pct_a, 50)
  expect_equal(result$common_pct_b, 200 / 3)
  expect_equal(result$n_rank_common, 2L)
  expect_equal(result$spearman_rho, 1)
})

test_that("paired differences match equipment keys and explicitly use A minus B", {
  a <- agreement_rows(c("a", "b", "c", "d"), distances = c(11, 23, 35, 47))
  b <- agreement_rows(c("d", "b", "a", "c"), ranks = c(4, 2, 1, 3),
    distances = c(40, 20, 10, 30), metric = "B")
  result <- metric_pair_agreement(a, b, k = 2L)
  # Matched A - B differences are 1, 3, 5, 7, despite B's different row order.
  expect_equal(result$n_distance_common, 4L)
  expect_equal(result$mean_difference_m, 4)
  expect_equal(result$median_difference_m, 4)
  expect_equal(result$p25_difference_m, 2.5)
  expect_equal(result$p75_difference_m, 5.5)
  expect_equal(result$iqr_difference_m, 3)
  expect_equal(result$sd_difference_m, sqrt(20 / 3))
  expect_equal(result$limits_lower_m, 4 - 1.96 * sqrt(20 / 3))
  expect_equal(result$limits_upper_m, 4 + 1.96 * sqrt(20 / 3))
  reverse <- metric_pair_agreement(b, a, k = 2L)
  expect_equal(reverse$mean_difference_m, -4)
  expect_equal(reverse$median_difference_m, -4)
  expect_equal(reverse$p25_difference_m, -5.5)
  expect_equal(reverse$p75_difference_m, -2.5)
  expect_equal(reverse$iqr_difference_m, 3)
  expect_equal(reverse$limits_lower_m, -result$limits_upper_m)
  expect_equal(reverse$limits_upper_m, -result$limits_lower_m)
})

test_that("automatic A minus B orientation is invariant to block and general row permutations", {
  a <- agreement_rows(letters[1:4], distances = c(11, 23, 35, 47), direction = "origin_to_equipment")
  b <- agreement_rows(letters[1:4], distances = c(10, 20, 30, 40), metric = "B")
  c <- agreement_rows(letters[1:4], distances = c(1, 2, 3, 4), direction = "equipment_to_origin")
  results_1 <- rbind(a, b, c)
  results_2 <- rbind(c, b, a)
  results_3 <- results_1[c(12, 2, 7, 5, 9, 3, 8, 1, 11, 4, 6, 10), ]
  first <- metric_agreement(results_1, k = 2L)
  second <- metric_agreement(results_2, k = 2L)
  third <- metric_agreement(results_3, k = 2L)
  columns <- c("metric_a", "direction_a", "metric_b", "direction_b", "mean_difference_m",
    "median_difference_m", "p25_difference_m", "p75_difference_m", "iqr_difference_m",
    "limits_lower_m", "limits_upper_m")
  expect_identical(first[, columns], second[, columns])
  expect_identical(first[, columns], third[, columns])
  expect_identical(first$metric_a, c("A", "A", "A"))
  expect_identical(first$direction_a, c("equipment_to_origin", "equipment_to_origin", "origin_to_equipment"))
  expect_identical(first$metric_b, c("A", "B", "B"))
  expect_identical(first$direction_b, c("origin_to_equipment", "symmetric", "symmetric"))
  expect_equal(first$mean_difference_m, c(-26.5, -22.5, 4))
  expect_identical(sign(first$mean_difference_m), c(-1, -1, 1))
  expect_identical(sign(first$mean_difference_m), sign(second$mean_difference_m))
  expect_identical(sign(first$mean_difference_m), sign(third$mean_difference_m))
})

test_that("distance summaries exclude any pair with a nonfinite distance on either side", {
  a <- agreement_rows(letters[1:7], distances = c(11, NA, Inf, 40, NaN, 60, -Inf))
  b <- agreement_rows(letters[1:7], distances = c(10, 20, 30, NaN, 50, 55, 70), metric = "B")
  expect_warning(result <- metric_pair_agreement(a, b, k = 2L), NA)
  expect_equal(result$n_common, 7L)
  expect_equal(result$n_rank_common, 7L)
  expect_equal(result$n_distance_common, 2L)
  expect_equal(result$mean_difference_m, 3)
  expect_equal(result$median_difference_m, 3)
  expect_equal(result$p25_difference_m, 2)
  expect_equal(result$p75_difference_m, 4)
  expect_equal(result$iqr_difference_m, 2)
  expect_equal(result$sd_difference_m, sqrt(8))
})

test_that("one distance pair has a signed summary but no estimable SD or limits", {
  a <- agreement_rows(letters[1:2], distances = c(12, NA))
  b <- agreement_rows(letters[1:2], distances = c(10, Inf), metric = "B")
  expect_warning(result <- metric_pair_agreement(a, b, k = 1L), NA)
  expect_equal(result$n_distance_common, 1L)
  expect_equal(result$mean_difference_m, 2)
  expect_equal(result$median_difference_m, 2)
  expect_equal(result$p25_difference_m, 2)
  expect_equal(result$p75_difference_m, 2)
  expect_equal(result$iqr_difference_m, 0)
  expect_identical(result$sd_difference_m, NA_real_)
  expect_identical(result$limits_lower_m, NA_real_)
  expect_identical(result$limits_upper_m, NA_real_)
})

test_that("no finite distance pair yields NA for every difference summary", {
  a <- agreement_rows(letters[1:3], distances = c(NA, Inf, NaN))
  b <- agreement_rows(letters[1:3], metric = "B")
  expect_warning(result <- metric_pair_agreement(a, b, k = 1L), NA)
  expect_equal(result$n_distance_common, 0L)
  columns <- c("mean_difference_m", "median_difference_m", "p25_difference_m", "p75_difference_m",
    "iqr_difference_m", "sd_difference_m", "limits_lower_m", "limits_upper_m")
  for (column in columns) expect_identical(result[[column]], NA_real_, label = column)
  expect_equal(result$top_k_jaccard, 1)
})

test_that("invalid insufficient and constant ranks do not force correlations", {
  a <- agreement_rows(letters[1:6], ranks = c(1, 2, NA, Inf, 0, -1))
  b <- agreement_rows(letters[1:6], metric = "B")
  result <- metric_pair_agreement(a, b, k = 2L)
  expect_equal(result$n_rank_common, 2L)
  expect_equal(result$spearman_rho, 1)
  expect_equal(result$kendall_tau, 1)
  b$rank <- rep(2, 6)
  expect_warning(constant <- metric_pair_agreement(a, b, k = 2L), NA)
  expect_equal(constant$n_rank_common, 2L)
  expect_true(is.na(constant$spearman_rho))
  expect_true(is.na(constant$kendall_tau))
  a$rank[2] <- NA
  expect_warning(single <- metric_pair_agreement(a, b, k = 2L), NA)
  expect_equal(single$n_rank_common, 1L)
  expect_true(is.na(single$spearman_rho))
  expect_true(is.na(single$kendall_tau))
})

test_that("rank ties are preserved rather than arbitrarily reordered", {
  a <- agreement_rows(letters[1:3], ranks = c(1, 1, 2))
  b <- agreement_rows(letters[1:3], ranks = c(1, 2, 2), metric = "B")
  result <- metric_pair_agreement(a, b, k = 1L)
  expect_equal(result$spearman_rho, 0.5)
  expect_equal(result$kendall_tau, 0.5)
  expect_equal(result$top_k_jaccard, 0.5)
})

test_that("ambiguous duplicates fail before any Cartesian pairing including a single metric", {
  a <- agreement_rows(letters[1:3])
  b <- agreement_rows(letters[1:3], metric = "B")
  duplicate <- rbind(a, a[1, ])
  expect_error(metric_agreement(rbind(duplicate, b)), "Pareamento ambiguo")
  expect_error(metric_agreement(duplicate), "Pareamento ambiguo")
  expect_error(metric_pair_agreement(duplicate, b, k = 1L), "Pareamento ambiguo")
  a$equipment_id[1] <- NA
  expect_error(metric_agreement(rbind(a, b)), "Identificador ausente")
})

test_that("metric identifiers and directions remain separate even with delimiter characters", {
  a <- agreement_rows(letters[1:2], metric = "A|ida", direction = "volta")
  b <- agreement_rows(letters[1:2], metric = "A", direction = "ida|volta")
  result <- metric_agreement(rbind(a, b))
  expect_equal(nrow(result), 1L)
  expect_identical(result$metric_a, "A")
  expect_identical(result$direction_a, "ida|volta")
  expect_identical(result$metric_b, "A|ida")
  expect_identical(result$direction_b, "volta")
  b$metric_id <- a$metric_id
  expect_equal(metric_agreement(rbind(a, b))$n_common, 2L)
})

test_that("origins are paired separately and empty observed sides have explicit coverage", {
  a1 <- agreement_rows(letters[1:3])
  b1 <- agreement_rows(letters[1:3], distances = c(110, 210, 310), metric = "B")
  a2 <- agreement_rows(letters[1:3], origin = "o2")
  b2 <- agreement_rows(letters[1:3], ranks = 3:1, distances = c(90, 180, 270), metric = "B", origin = "o2")
  result <- metric_agreement(rbind(a1, b1, a2, b2))
  result <- result[match(c("o1", "o2"), result$origin_id), ]
  expect_equal(result$n_common, c(3L, 3L))
  expect_equal(result$spearman_rho, c(1, -1))
  expect_equal(result$mean_difference_m, c(-10, 20))
  expect_error(metric_pair_agreement(a1, b2, k = 1L), "mesma origem")
  expect_error(metric_pair_agreement(rbind(a1, a2), b1, k = 1L), "unico estrato")
  missing_side <- metric_agreement(rbind(a1, a2, b2))
  first <- missing_side[missing_side$origin_id == "o1", ]
  expect_equal(first$n_a, 3L)
  expect_equal(first$n_b, 0L)
  expect_equal(first$n_common, 0L)
  expect_equal(first$common_pct_a, 0)
  expect_identical(first$common_pct_b, NA_real_)
  expect_equal(first$top_k_jaccard, 0)
  empty <- a1[0, ]
  both_empty <- metric_pair_agreement(empty, empty, k = 1L)
  expect_identical(both_empty$common_pct_a, NA_real_)
  expect_identical(both_empty$common_pct_b, NA_real_)
  expect_true(is.na(both_empty$top_k_jaccard))
})

test_that("fastest compares existing time ranks but uses selected route lengths for differences", {
  a <- agreement_rows(letters[1:3], distances = c(300, 100, 200), metric = "network_foot_fastest",
    direction = "origin_to_equipment")
  b <- agreement_rows(letters[1:3], distances = c(10, 30, 20), metric = "network_foot_fastest",
    direction = "equipment_to_origin")
  a$path_objective <- b$path_objective <- "fastest"
  a$duration_min <- b$duration_min <- 1:3
  input <- rbind(a, b)
  original <- input
  result <- metric_agreement(input, k = 1L)
  expect_identical(input, original)
  expect_identical(result$direction_a, "equipment_to_origin")
  expect_identical(result$direction_b, "origin_to_equipment")
  expect_equal(result$spearman_rho, 1)
  expect_equal(result$kendall_tau, 1)
  expect_equal(result$top_k_jaccard, 1)
  expect_equal(result$mean_difference_m, -180)
  expect_equal(result$median_difference_m, -180)
  expect_equal(result$iqr_difference_m, 110)
  expect_equal(result$sd_difference_m, 110)
})

test_that("empty or single-metric inputs have a stable schema and invalid k is rejected", {
  empty <- metric_agreement(data.frame())
  expect_equal(nrow(empty), 0L)
  expect_identical(empty, metric_agreement(agreement_rows("a")))
  expect_true(all(c("origin_id", "metric_a", "direction_a", "metric_b", "direction_b",
    "n_a", "n_b", "n_common", "n_rank_common", "n_distance_common", "k") %in% names(empty)))
  for (k in c(0, -1, 1.5, NA, Inf)) expect_error(metric_agreement(data.frame(), k), "k deve")
})

test_that("app comparison wrapper preserves origin-specific k and new identifiers", {
  a1 <- agreement_rows(letters[1:3])
  b1 <- agreement_rows(letters[1:3], ranks = 3:1, metric = "B")
  a2 <- agreement_rows(letters[1:3], origin = "o2")
  b2 <- agreement_rows(letters[1:3], ranks = 3:1, metric = "B", origin = "o2")
  input <- rbind(a1, b1, a2, b2)
  input$selection_k <- ifelse(input$origin_id == "o1", 1L, 2L)
  result <- proximity_agreement(input)
  expect_equal(result$k, c(1L, 2L))
  expect_equal(result$top_k_jaccard, c(0, 1 / 3))
  expect_equal(result$direction_a, rep("symmetric", 2))
  expect_equal(result$direction_b, rep("symmetric", 2))
})

test_that("report keeps ordering coverage and signed distance differences in separate tables", {
  a <- agreement_rows(letters[1:3], distances = c(11, 23, 35), direction = "origin_to_equipment")
  b <- agreement_rows(letters[1:3], distances = c(10, 20, 30), metric = "B", direction = "equipment_to_origin")
  input <- rbind(a, b)
  input$selection_k <- 2L
  path <- system.file("reports", "proximity_report.Rmd", package = "sampamaisrural")
  if (!nzchar(path)) path <- file.path(project_root(), "inst", "reports", "proximity_report.Rmd")
  lines <- readLines(path, warn = FALSE)
  start <- which(lines == "```{r agreement}")
  stopifnot(length(start) == 1L)
  end <- start + which(lines[seq.int(start + 1L, length(lines))] == "```")[1]
  report <- new.env(parent = asNamespace("sampamaisrural"))
  report$results <- input
  report$abbreviate_metric <- identity
  tables <- captions <- list()
  report$report_table <- function(x, caption = NULL, ...) {
    tables[[length(tables) + 1L]] <<- x
    captions[[length(captions) + 1L]] <<- caption
  }
  eval(parse(text = lines[seq.int(start + 1L, end - 1L)]), report)
  expect_length(tables, 2L)
  expect_equal(tables[[1]]$n_a, 3L)
  expect_equal(tables[[1]]$n_b, 3L)
  expect_equal(tables[[1]]$n_common, 3L)
  expect_equal(tables[[1]]$common_pct_a, 100)
  expect_equal(tables[[1]]$common_pct_b, 100)
  expect_equal(tables[[1]]$n_rank_common, 3L)
  expect_equal(tables[[1]]$top_k_jaccard, 1)
  expect_equal(tables[[1]]$k, 2L)
  expect_equal(tables[[2]]$n_distance_common, 3L)
  expect_equal(tables[[2]]$median_difference_m, 3)
  expect_equal(tables[[2]]$p25_difference_m, 2)
  expect_equal(tables[[2]]$p75_difference_m, 4)
  expect_equal(tables[[2]]$iqr_difference_m, 2)
  expect_equal(tables[[2]]$mean_difference_m, 3)
  expect_equal(tables[[2]]$sd_difference_m, 2)
  expect_false("mean_difference_m" %in% names(tables[[1]]))
  expect_false("spearman_rho" %in% names(tables[[2]]))
  expect_identical(tables[[1]]$direction_a, "origin_to_equipment")
  expect_identical(tables[[2]]$direction_b, "equipment_to_origin")
  expect_match(captions[[2]], "A menos B")
})
