descriptive_fixture <- function() {
  strata <- expand.grid(origin_id = c("o1", "o2"), metric_id = c("metric_a", "metric_b"),
    direction = c("origin_to_equipment", "equipment_to_origin"), stringsAsFactors = FALSE)
  dplyr::bind_rows(lapply(seq_len(nrow(strata)), function(i) {
    data.frame(strata[rep(i, 5), ], metric_label = "Mesmo rotulo",
      equipment_id = c("a", "b", "c", "c", "d"),
      distance_m = c(0, 10, 20, 30, NA) + (i - 1) * 100,
      within_radius = c(TRUE, FALSE, TRUE, FALSE, NA),
      path_objective = "fastest", rank = 1:5, duration_min = c(5, 1, 3, 4, NA),
      stringsAsFactors = FALSE, row.names = NULL)
  }))
}

descriptive_report_chunk <- function(label) {
  path <- system.file("reports", "proximity_report.Rmd", package = "sampamaisrural")
  if (!nzchar(path)) path <- file.path(project_root(), "inst", "reports", "proximity_report.Rmd")
  lines <- readLines(path, warn = FALSE)
  start <- grep(paste0("^```\\{r ", label, "[,}]"), lines)
  stopifnot(length(start) == 1L)
  end <- start + which(lines[seq.int(start + 1L, length(lines))] == "```")[1]
  parse(text = lines[seq.int(start + 1L, end - 1L)])
}

descriptive_app_output <- function(name) {
  target <- call("$", as.name("output"), as.name(name))
  expressions <- Filter(function(expr) is.call(expr) && identical(expr[[1]], as.name("<-")) &&
    identical(expr[[2]], target), as.list(body(app_server))[-1])
  stopifnot(length(expressions) == 1L)
  expressions[[1]]
}

test_that("group listing exposes stable local group identifiers without loading data", {
  local_mocked_bindings(read_sampa_config = function(...) stop("Configuration not needed"),
    .package = "sampamaisrural")
  catalog <- list_equipment_groups()
  expect_named(catalog, c("group_id", "label"))
  expect_identical(catalog$group_id, c("feiras_livres", "feiras_organicas", "hortifruti",
    "abastecimento", "organicos", "hortas", "agricultores", "alimentacao", "apoio", "conexoes", "outros"))
  expect_equal(catalog$label[c(1, 6, 11)], c("Feiras livres", "Hortas urbanas e institucionais", "Outros registros da fonte"))
  expect_false(anyDuplicated(catalog$group_id) > 0L)
  expect_true(all(nzchar(catalog$label)))
  expect_true("list_equipment_groups" %in% getNamespaceExports("sampamaisrural"))
  expect_false(exists("list_equipment_categories", envir = asNamespace("sampamaisrural"), inherits = FALSE))
})

test_that("group counts reuse multilabel coverage and spatial eligibility locally", {
  local_mocked_bindings(perform_request = function(...) stop("Network forbidden"),
    .package = "sampamaisrural")
  directory <- withr::local_tempdir()
  config <- read_sampa_config(overrides = list(data_dir = directory))
  equipment <- demo_equipment()[1:4, ]
  equipment$equipment_name <- c("Feira organica CEAGESP", "Horta escolar", "Registro sem grupo", "Feira organica CEAGESP")
  equipment$category <- "Cadastro"
  equipment$latitude <- c(-23.55, NA, -23.55, -22)
  equipment$longitude <- -46.63
  catalog <- list_equipment_groups(equipment, config)
  expect_named(catalog, c("group_id", "label", "registros", "mapeaveis"))
  expect_equal(catalog$registros, c(0, 2, 0, 2, 2, 1, 0, 0, 0, 0, 1))
  expect_equal(catalog$mapeaveis, c(0, 1, 0, 1, 1, 0, 0, 0, 0, 0, 1))
  expect_gt(sum(catalog$registros), nrow(equipment))
  empty <- list_equipment_groups(equipment[0, ], config)
  expect_identical(empty$group_id, catalog$group_id)
  expect_true(all(empty$registros == 0L))
  expect_true(all(empty$mapeaveis == 0L))
  expect_length(list.files(directory, all.files = TRUE, recursive = TRUE, no.. = TRUE), 0L)
})

test_that("descriptive summaries keep origins metrics and directions separate with exact values", {
  results <- descriptive_fixture()
  original <- results
  summary <- proximity_summary(results)
  keys <- c("origin_id", "metric_id", "direction")
  strata <- unique(results[, keys])
  ordered <- dplyr::left_join(strata, summary, by = keys)
  offsets <- seq(0, 700, by = 100)
  expect_equal(nrow(summary), 8L)
  expect_identical(results, original)
  expect_equal(ordered$pares_retidos, rep(5L, 8))
  expect_equal(ordered$pares_distancia_valida, rep(4L, 8))
  expect_equal(ordered$pares_distancia_ausente, rep(1L, 8))
  expect_equal(ordered$pares_retidos, ordered$pares_distancia_valida + ordered$pares_distancia_ausente)
  expect_equal(ordered$equipamentos, rep(4L, 8))
  expect_equal(ordered$no_raio, rep(2L, 8))
  expect_equal(ordered$minimo_m, offsets)
  expect_equal(ordered$p25_m, offsets + 7.5)
  expect_equal(ordered$mediana_m, offsets + 15)
  expect_equal(ordered$p75_m, offsets + 22.5)
  expect_equal(ordered$iqr_m, rep(15, 8))
  expect_equal(ordered$p90_m, offsets + 27)
  expect_equal(ordered$maximo_m, offsets + 30)
  expect_equal(ordered$metric_label, rep("Mesmo rotulo", 8))
})

test_that("nonfinite retained distances never become zero or override radius flags", {
  results <- descriptive_fixture()[1:4, ]
  results$distance_m <- c(NA, NaN, Inf, -Inf)
  results$within_radius <- c(TRUE, TRUE, FALSE, NA)
  summary <- proximity_summary(results)
  expect_equal(summary$pares_retidos, 4L)
  expect_equal(summary$pares_distancia_valida, 0L)
  expect_equal(summary$pares_distancia_ausente, 4L)
  expect_equal(summary$equipamentos, 3L)
  expect_equal(summary$no_raio, 2L)
  distance_columns <- c("minimo_m", "p25_m", "mediana_m", "p75_m", "iqr_m", "p90_m", "maximo_m")
  for (column in distance_columns) expect_identical(summary[[column]], NA_real_, label = column)

  results$distance_m <- c(NA, 10, Inf, 30)
  mixed <- proximity_summary(results)
  expect_equal(mixed$pares_distancia_valida, 2L)
  expect_equal(mixed$pares_distancia_ausente, 2L)
  expect_equal(mixed$minimo_m, 10)
  expect_equal(mixed$p25_m, 15)
  expect_equal(mixed$mediana_m, 20)
  expect_equal(mixed$p75_m, 25)
  expect_equal(mixed$iqr_m, 10)
  expect_equal(mixed$p90_m, 28)
  expect_equal(mixed$maximo_m, 30)
  expect_equal(mixed$no_raio, 2L)
})

test_that("descriptive summaries preserve the columns consumed by the app", {
  results <- descriptive_fixture()[1:4, ]
  summary <- proximity_summary(results)
  legacy_columns <- c("origin_id", "metric_label", "direction", "equipamentos", "no_raio",
    "minimo_m", "mediana_m", "p90_m", "maximo_m")
  expect_true(all(legacy_columns %in% names(summary)))
  expect_equal(summary[, legacy_columns], data.frame(origin_id = "o1", metric_label = "Mesmo rotulo",
    direction = "origin_to_equipment", equipamentos = 3L, no_raio = 2L,
    minimo_m = 0, mediana_m = 15, p90_m = 27, maximo_m = 30))
  expect_true("proximity_summary" %in% getNamespaceExports("sampamaisrural"))
  results$metric_label <- NULL
  expect_identical(proximity_summary(results)$metric_label, "metric_a")
  results$metric_id <- NULL
  expect_error(proximity_summary(results), "metric_id")
})

test_that("empty descriptive input returns a stable typed schema", {
  empty <- proximity_summary(data.frame())
  expect_identical(empty, proximity_summary(descriptive_fixture()[0, ]))
  expect_equal(nrow(empty), 0L)
  expect_named(empty, c("origin_id", "metric_id", "direction", "metric_label",
    "pares_retidos", "pares_distancia_valida", "pares_distancia_ausente", "equipamentos", "no_raio",
    "minimo_m", "p25_m", "mediana_m", "p75_m", "iqr_m", "p90_m", "maximo_m"))
  for (column in c("pares_retidos", "pares_distancia_valida", "pares_distancia_ausente", "equipamentos", "no_raio")) {
    expect_identical(empty[[column]], integer(), label = column)
  }
  for (column in c("minimo_m", "p25_m", "mediana_m", "p75_m", "iqr_m", "p90_m", "maximo_m")) {
    expect_identical(empty[[column]], numeric(), label = column)
  }
})

test_that("app consumers reuse the central summary and handle invalid distances", {
  original_summary <- proximity_summary
  calls <- list()
  local_mocked_bindings(proximity_summary = function(results) {
    calls[[length(calls) + 1L]] <<- results
    original_summary(results)
  }, .package = "sampamaisrural")
  results <- descriptive_fixture()
  consumers <- lapply(c("query_kpis", "summary_table", "distance_plot"), descriptive_app_output)
  # Evaluate only these consumers, without starting the app's worker or polling.
  server <- function(input, output, session) {
    result_state <- shiny::reactiveVal(results)
    for (consumer in consumers) eval(consumer)
  }
  shiny::testServer(server, {
    session$setInputs(map_metric = "metric_a")
    expect_match(output$query_kpis$html, "resumo por origem e sentido")
    expect_no_error(output$summary_table)
    expect_setequal(vapply(calls, nrow, integer(1)), c(20L, 40L))
    result_state(results[1:4, ])
    session$flushReact()
    expect_match(output$query_kpis$html, "n v\u00e1lido = 4")
    expect_match(output$query_kpis$html, "0 m")
    invalid <- results[1:4, ]
    invalid$distance_m <- c(NA, NaN, Inf, -Inf)
    result_state(invalid)
    session$flushReact()
    expect_match(output$query_kpis$html, "n v\u00e1lido = 0")
    expect_match(output$query_kpis$html, "N\u00e3o dispon\u00edvel")
    expect_error(output$distance_plot, "N\u00e3o h\u00e1 dist\u00e2ncias finitas", class = "shiny.silent.error")
  })
})

test_that("report summary and ECDF preserve strata and their valid denominators", {
  results <- descriptive_fixture()
  report <- new.env(parent = asNamespace("sampamaisrural"))
  report$results <- results
  report$abbreviate_metric <- identity
  tables <- list()
  report$report_table <- function(x, ...) tables[[length(tables) + 1L]] <<- x
  eval(descriptive_report_chunk("summary"), report)
  expect_equal(report$summary_table, proximity_summary(results))
  expect_length(tables, 2L)
  expect_equal(tables[[1]]$pares_retidos, rep(5L, 8))
  expect_equal(tables[[2]]$pares_distancia_valida, rep(4L, 8))
  expect_equal(tables[[2]]$iqr_m, rep(15, 8))
  expect_true(all(c("origin_id", "metric_id", "direction") %in% names(tables[[2]])))

  plot <- NULL
  report$page_break <- function() NULL
  report$print <- function(x, ...) plot <<- x
  eval(descriptive_report_chunk("chart"), report)
  expect_s3_class(plot, "ggplot")
  expect_equal(nrow(plot$data), 32L)
  expect_true(all(is.finite(plot$data$distance_m)))
  built <- ggplot2::ggplot_build(plot)
  expect_equal(nrow(built$layout$layout), 4L)
  expect_setequal(built$layout$layout$origin_id, c("o1", "o2"))
  expect_setequal(built$layout$layout$direction, c("origin_to_equipment", "equipment_to_origin"))
  curves <- split(built$data[[1]], built$data[[1]]$group)
  expect_length(curves, 8L)
  for (curve in curves) expect_equal(sort(unique(curve$y)), c(0, 0.25, 0.5, 0.75, 1))
})

test_that("report ECDF handles strata with no finite distance explicitly", {
  report <- new.env(parent = asNamespace("sampamaisrural"))
  report$results <- descriptive_fixture()[1:4, ]
  report$results$distance_m <- c(NA, NaN, Inf, -Inf)
  report$page_break <- function() NULL
  report$print <- function(...) stop("No curve should be drawn")
  output <- capture.output(eval(descriptive_report_chunk("chart"), report))
  expect_match(paste(output, collapse = "\n"), "Nenhuma distancia finita")
})
