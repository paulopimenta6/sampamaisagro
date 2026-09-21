test_that("quality counts the full inventory while space only uses eligible profiles", {
  cfg <- v02_test_config(); v02_forbid_http()
  eq <- v02_quality(v02_fixtures)
  checked <- validate_equipment(eq, cfg)
  expect_equal(checked$summary$n, 4L)
  expect_equal(checked$summary$coordinate_n, 2L)
  expect_equal(checked$summary$coordinate_pct, 50)
  result <- calculate_proximity(v02_origin(v02_fixtures), eq, modes = character(), config = cfg)
  expect_setequal(result$equipment_id, checked$eligible$equipment_id)
  expect_false(any(eq$equipment_id[3:4] %in% result$equipment_id))
})

test_that("Shiny report receives the frozen full filtered inventory", {
  cfg <- v02_test_config(); v02_forbid_http()
  captured <- NULL
  local_mocked_bindings(render_proximity_report = function(results, output_file, origins = NULL,
    equipment = NULL, config = NULL, quality_context = NULL) {
    captured <<- list(equipment = equipment, quality_context = quality_context, results = results)
    writeLines("fixture report", output_file)
  })
  # Drive the real worker synchronously to test the server/download contract
  # without depending on wall-clock scheduling or a browser.
  for (requested_modes in list(character(), "motorcar")) {
  pool <- new_web_pool(function(path) {
    web_job_worker(file.path(path, "request.rds"))
    list(is_alive = function() FALSE, get_result = function() NULL)
  })
  server <- function(input, output, session) app_server(input, output, session,
    config = cfg, equipment = v02_quality(v02_fixtures), graphs = list(), context = list(), pool = pool)
  shiny::testServer(server, {
    session$setInputs(categories = "hortas", accessibility = "all", origin_method = "coordinates",
      latitude = -23.612345, longitude = -46.712345, query_k = 10, query_radius = 1000,
      query_modes = requested_modes, query_direction = "both", main_nav = "statistics")
    session$setInputs(run_query = 1)
    session$elapse(600); session$elapse(600)
    session$setInputs(categories = "outros", accessibility = "yes")
    path <- output$download_report
    expect_true(file.exists(path))
    expect_equal(nrow(captured$equipment), 4L)
    expect_equal(nrow(validate_equipment(captured$equipment, cfg)$eligible), 2L)
    expect_equal(captured$quality_context$groups, "hortas")
    expect_equal(captured$quality_context$accessibility, "all")
    expect_equal(captured$quality_context$global_n, 4L)
    expect_equal(attr(captured$results, "analysis")$status,
      if (length(requested_modes)) "failed" else "completed")
    session$setInputs(categories = "hortas", run_query = 2)
    session$elapse(600); session$elapse(600)
    path <- output$download_report
    expect_equal(nrow(captured$equipment), 1L)
    expect_equal(captured$quality_context$groups, "hortas")
    expect_equal(captured$quality_context$accessibility, "yes")
    expect_equal(captured$quality_context$global_n, 4L)
  })
  }
})

test_that("HTML quality uses 4/2/50 and partial results keep the same denominator", {
  skip_if_not(rmarkdown::pandoc_available())
  cfg <- v02_test_config(); v02_forbid_http()
  eq <- v02_quality(v02_fixtures)
  result <- calculate_proximity(v02_origin(v02_fixtures), eq, modes = character(), config = cfg)
  groups <- names(v02_internal("equipment_groups"))
  context <- list(groups = c(groups, "hortas_50% & teste"), accessibility = "all", global_n = 7L, snapshot = "synthetic-v02")
  filter_rows <- function(target) {
    html <- paste(readLines(target, warn = FALSE), collapse = " ")
    rows <- regmatches(html, gregexpr("<tr[^>]*>.*?</tr>", html, perl = TRUE))[[1]]
    rows <- rows[grepl(">[[:space:]]*Grupos solicitados[[:space:]]*</td>", rows)]
    values <- sub(".*?</td>[[:space:]]*<td[^>]*>(.*?)</td>.*", "\\1", rows, perl = TRUE)
    trimws(gsub("&amp;", "&", values, fixed = TRUE))
  }
  for (status in c("completed", "cancelled")) {
    attr(result, "analysis") <- list(status = status, completed_units = 1L, total_units = 2L,
      requested_modes = "motorcar", stage = "fixture")
    target <- file.path(cfg$reports_dir, paste0(status, ".html"))
    render_proximity_report(result, target, equipment = eq, config = cfg, quality_context = context)
    html <- paste(readLines(target, warn = FALSE), collapse = " ")
    expect_match(html, "Inventário filtrado da consulta", fixed = TRUE)
    expect_match(html, "synthetic-v02", fixed = TRUE)
    expect_match(html, "hortas_50% &amp; teste", fixed = TRUE)
    expect_equal(filter_rows(target), context$groups)
    # Read the actual rendered quality table, not a snapshot of HTML bytes.
    table <- regmatches(html, regexpr('<table[^>]*id="quality-by-category".*?</table>', html, perl = TRUE))
    cells <- regmatches(table, gregexpr('<td[^>]*>.*?</td>', table, perl = TRUE))[[1]]
    cells <- gsub('<[^>]+>', '', cells)
    expect_equal(trimws(cells[1]), "Agricultura")
    expect_equal(as.numeric(cells[2:4]), c(4, 2, 50))
    if (status == "cancelled") expect_match(html, "RESULTADOS PARCIAIS", fixed = TRUE)
  }
  # Backward-compatible positional invocation remains supported.
  legacy <- file.path(cfg$reports_dir, "legacy.html")
  render_proximity_report(result, legacy, NULL, eq, cfg)
  expect_match(paste(readLines(legacy, warn = FALSE), collapse = " "), "Inventário fornecido", fixed = TRUE)
  for (selection in list(groups[1], groups[1:3], character())) {
    context$groups <- selection
    target <- file.path(cfg$reports_dir, paste0("filters-", length(selection), ".html"))
    render_proximity_report(result, target, equipment = eq, config = cfg, quality_context = context)
    expect_equal(filter_rows(target), if (length(selection)) selection else "Todos")
  }
})

test_that("PDF quality renders with special characters when pdflatex is available", {
  skip_if_not(rmarkdown::pandoc_available(), "Pandoc unavailable: PDF rendering was not exercised")
  skip_if(!nzchar(Sys.which("pdflatex")), "pdflatex unavailable: PDF compilation was not exercised")
  # An installed but incomplete/broken LaTeX must fail, not skip or download packages.
  withr::local_options(tinytex.install_packages = FALSE)
  cfg <- v02_test_config(); v02_forbid_http()
  eq <- v02_quality(v02_fixtures)
  eq$category <- "Categoria_50% & teste"
  result <- calculate_proximity(v02_origin(v02_fixtures), eq, modes = character(), config = cfg)
  context <- list(groups = "hortas_50% & teste", accessibility = "all",
    global_n = 7L, snapshot = "synthetic_v02_50%")
  target <- file.path(cfg$reports_dir, "quality-special-characters.pdf")
  expect_no_error(render_proximity_report(result, target, equipment = eq,
    config = cfg, quality_context = context))
  expect_true(file.exists(target))
  expect_identical(readChar(target, nchars = 5L, useBytes = TRUE), "%PDF-")
})

test_that("PDF retains every requested group visibly within the page", {
  skip_if_not(rmarkdown::pandoc_available(), "Pandoc unavailable: PDF context was not exercised")
  skip_if(!nzchar(Sys.which("pdflatex")), "pdflatex unavailable: PDF context was not exercised")
  skip_if(!nzchar(Sys.which("pdftotext")), "pdftotext unavailable: PDF content/bounds were not checked")
  withr::local_options(tinytex.install_packages = FALSE)
  cfg <- v02_test_config(); v02_forbid_http()
  eq <- v02_quality(v02_fixtures)
  result <- calculate_proximity(v02_origin(v02_fixtures), eq, modes = character(), config = cfg)
  groups <- names(v02_internal("equipment_groups"))
  context <- list(groups = groups, accessibility = "all", global_n = 7L, snapshot = "synthetic-v02")
  target <- file.path(cfg$reports_dir, "quality-all-groups.pdf")
  render_proximity_report(result, target, equipment = eq, config = cfg, quality_context = context)
  bbox <- file.path(cfg$reports_dir, "quality-all-groups-bbox.html")
  expect_equal(system2(Sys.which("pdftotext"), c("-bbox", shQuote(target), shQuote(bbox))), 0L)
  # Bounds detect text extending off the page even if extraction retains it.
  lines <- readLines(bbox, warn = FALSE)
  pages <- grep("<page ", lines, fixed = TRUE)
  attribute <- function(x, name) as.numeric(sub(paste0('.* ', name, '="([^"]+)".*'), "\\1", x))
  for (group in groups) {
    hits <- grep(paste0(">", group, "</word>"), lines, fixed = TRUE)
    expect_gt(length(hits), 0L, label = group)
    words <- lines[hits]
    page <- lines[pages[findInterval(hits, pages)]]
    expect_true(all(attribute(words, "xMin") >= 0 & attribute(words, "xMax") <= attribute(page, "width") &
      attribute(words, "yMin") >= 0 & attribute(words, "yMax") <= attribute(page, "height")), info = group)
  }
})

test_that("empty or entirely ineligible inventories never imply complete coordinate coverage", {
  cfg <- v02_test_config(); eq <- v02_quality(v02_fixtures)[3:4, ]
  checked <- validate_equipment(eq, cfg)
  expect_equal(checked$summary$n, 2)
  expect_equal(checked$summary$coordinate_pct, 0)
  expect_equal(nrow(checked$eligible), 0)
  expect_equal(nrow(calculate_proximity(v02_origin(v02_fixtures), eq, config = cfg)), 0)
  expect_equal(nrow(validate_equipment(eq[FALSE, ], cfg)$summary), 0)
  expect_error(render_proximity_report(data.frame(), tempfile(fileext = ".html"), equipment = eq, config = cfg),
    "consulta com resultados")
})
