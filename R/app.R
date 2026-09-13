app_ui <- function(config) {
  theme <- bslib::bs_theme(version = 5, bootswatch = "flatly", primary = "#176b3a")
  methodology <- system.file("app", "methodology.md", package = "sampamaisrural")
  if (!nzchar(methodology)) methodology <- file.path(project_root(), "inst", "app", "methodology.md")
  bslib::page_navbar(
    title = "Sampa+Rural | proximidade",
    theme = theme, id = "main_nav",
    header = shiny::tags$head(
      shiny::tags$link(rel = "stylesheet", type = "text/css", href = "sampamaisrural-assets/app.css"),
      shiny::tags$link(rel = "icon", href = "data:,"),
      shiny::tags$meta(name = "description", content = "Analise academica de proximidade aos equipamentos Sampa+Rural")
    ),
    bslib::nav_panel("Consulta",
      bslib::layout_sidebar(
        sidebar = bslib::sidebar(
          shiny::radioButtons("origin_method", "Origem", c("Latitude/longitude" = "coordinates", "CEP" = "cep")),
          shiny::conditionalPanel("input.origin_method == 'coordinates'",
            shiny::numericInput("latitude", "Latitude", -23.5505, min = -90, max = 90, step = 0.0001),
            shiny::numericInput("longitude", "Longitude", -46.6333, min = -180, max = 180, step = 0.0001)
          ),
          shiny::conditionalPanel("input.origin_method == 'cep'",
            shiny::textInput("cep", "CEP", placeholder = "00000-000")
          ),
          shiny::selectizeInput("categories", "Categorias", choices = NULL, multiple = TRUE,
            options = list(placeholder = "Todas")),
          shiny::numericInput("query_k", "Vizinhos por metrica", config$proximity$default_k, min = 1, max = 100),
          shiny::numericInput("query_radius", "Raio (m)", config$proximity$default_radius_m, min = 1, max = 100000),
          shiny::checkboxGroupInput("query_modes", "Modos de rede", choices = c(
            "Caminhada" = "foot", "Bicicleta" = "bicycle", "Automovel" = "motorcar"),
            selected = config$network$modes),
          shiny::selectInput("query_direction", "Sentido da rede", choices = c(
            "Origem para equipamento" = "origin_to_equipment",
            "Equipamento para origem" = "equipment_to_origin", "Ambos" = "both")),
          shiny::actionButton("run_query", "Calcular proximidade", class = "btn-primary w-100"),
          shiny::hr(),
          shiny::downloadButton("download_results", "Baixar CSV", class = "w-100"),
          shiny::downloadButton("download_report", "Relatorio HTML", class = "w-100 mt-2")
        ),
        shiny::uiOutput("data_notice"),
        shiny::uiOutput("query_status"),
        shiny::selectInput("map_metric", "Metrica exibida", choices = character()),
        leaflet::leafletOutput("proximity_map", height = "540px"),
        DT::DTOutput("proximity_table")
      )
    ),
    bslib::nav_panel("Lotes",
      bslib::layout_columns(
        bslib::card(
          bslib::card_header("Enviar arquivo"),
          shiny::p("CSV, TSV, XLSX ou Parquet com query_id e CEP, ou latitude e longitude."),
          shiny::fileInput("batch_file", "Arquivo", accept = c(".csv", ".tsv", ".xlsx", ".xls", ".parquet")),
          shiny::actionButton("submit_batch", "Adicionar a fila", class = "btn-primary"),
          shiny::uiOutput("batch_message"),
          shiny::hr(),
          shiny::textInput("batch_download_id", "ID de lote concluido"),
          shiny::downloadButton("download_batch", "Baixar resultados (.zip)")
        ),
        bslib::card(bslib::card_header("Fila duravel"), DT::DTOutput("jobs_table")),
        col_widths = c(4, 8)
      )
    ),
    bslib::nav_panel("Estatisticas",
      bslib::layout_columns(
        bslib::card(bslib::card_header("Cobertura por categoria"), shiny::plotOutput("category_plot")),
        bslib::card(bslib::card_header("Concordancia das metricas"), DT::DTOutput("agreement_table")),
        col_widths = c(6, 6)
      )
    ),
    bslib::nav_panel("Qualidade",
      shiny::h2("Diagnostico dos dados"),
      shiny::p("Registros sem coordenadas validas permanecem contabilizados, mas nao entram no calculo espacial."),
      DT::DTOutput("quality_table"), DT::DTOutput("issues_table")
    ),
    bslib::nav_panel("Metodologia",
      shiny::includeMarkdown(methodology)
    ),
    footer = shiny::div(class = "app-footer",
      "Uso academico. Cite o Sampa+Rural, a Prefeitura de Sao Paulo, as fontes parceiras e o OpenStreetMap.")
  )
}

app_server <- function(input, output, session, config, equipment, graphs) {
  validated <- validate_equipment(equipment, config)
  equipment <- validated$data
  shiny::updateSelectizeInput(session, "categories", choices = sort(unique(stats::na.omit(equipment$category))), server = TRUE)
  result_state <- shiny::reactiveVal(data.frame())
  origin_state <- shiny::reactiveVal(data.frame())
  status_state <- shiny::reactiveVal("Informe uma origem e execute a consulta.")

  output$data_notice <- shiny::renderUI({
    network_note <- if (!length(graphs)) " Grafos de rede ainda nao foram instalados; somente metricas geometricas serao calculadas." else ""
    if (isTRUE(all(equipment$coordinate_origin == "synthetic", na.rm = TRUE))) {
      shiny::div(class = "alert alert-warning", role = "alert",
        paste0("Modo demonstracao: carregue um snapshot oficial com scripts/update_data.R antes de interpretar resultados.",
          network_note))
    } else {
      shiny::div(class = "alert alert-info", role = "status",
        paste0(sprintf("Snapshot %s: %s registros; %s elegiveis espacialmente.",
          paste(unique(stats::na.omit(equipment$snapshot_date)), collapse = ", "), nrow(equipment), nrow(validated$eligible)),
          network_note))
    }
  })
  output$query_status <- shiny::renderUI(shiny::div(class = "query-status", status_state()))

  shiny::observeEvent(input$run_query, {
    status_state("Calculando...")
    origin <- if (identical(input$origin_method, "cep")) {
      data.frame(query_id = "consulta-1", cep = input$cep, k = input$query_k, radius_m = input$query_radius)
    } else {
      data.frame(query_id = "consulta-1", latitude = input$latitude, longitude = input$longitude,
        k = input$query_k, radius_m = input$query_radius)
    }
    resolved <- tryCatch(resolve_origins(origin, config), error = identity)
    if (inherits(resolved, "error") || !nrow(resolved$valid)) {
      message <- if (inherits(resolved, "error")) conditionMessage(resolved) else
        paste(unique(resolved$errors$message), collapse = "; ")
      status_state(paste("Consulta invalida:", message))
      result_state(data.frame())
      return()
    }
    result <- tryCatch(calculate_proximity(
      resolved$valid, equipment, graphs = graphs, categories = input$categories,
      k = input$query_k, radius_m = input$query_radius,
      modes = input$query_modes, directions = input$query_direction, config = config
    ), error = identity)
    if (inherits(result, "error")) {
      status_state(paste("Falha:", conditionMessage(result)))
      result_state(data.frame())
      return()
    }
    origin_map <- resolved$valid
    names(origin_map)[names(origin_map) == "query_id"] <- "origin_id"
    origin_state(origin_map)
    result_state(result)
    keys <- unique(result$metric_id)
    shiny::updateSelectInput(session, "map_metric", choices = keys, selected = keys[[1]])
    status_state(sprintf("Consulta concluida: %d combinacoes selecionadas.", nrow(result)))
  })

  output$proximity_map <- leaflet::renderLeaflet({
    make_leaflet_map(result_state(), origin_state(), input$map_metric)
  })
  output$proximity_table <- DT::renderDT({
    result <- result_state()
    shown <- intersect(c("origin_id", "equipment_name", "category", "metric_label", "mode", "direction",
      "rank", "distance_m", "duration_min", "within_radius", "routing_status"), names(result))
    table <- DT::datatable(result[, shown, drop = FALSE], rownames = FALSE, filter = "top",
      options = list(pageLength = 15, scrollX = TRUE))
    numeric_columns <- intersect(c("distance_m", "duration_min"), shown)
    if (length(numeric_columns)) table <- DT::formatRound(table, numeric_columns, 1)
    table
  })
  output$download_results <- shiny::downloadHandler(
    filename = function() paste0("proximidade-", Sys.Date(), ".csv"),
    content = function(file) readr::write_csv(result_state(), file, na = "")
  )
  output$download_report <- shiny::downloadHandler(
    filename = function() paste0("relatorio-proximidade-", Sys.Date(), ".html"),
    content = function(file) render_proximity_report(result_state(), file, origin_state(), equipment, config)
  )

  output$quality_table <- DT::renderDT(DT::datatable(validated$summary, rownames = FALSE,
    options = list(dom = "tip", pageLength = 20)))
  output$issues_table <- DT::renderDT(DT::datatable(validated$issues, rownames = FALSE,
    options = list(dom = "t")))
  output$category_plot <- shiny::renderPlot({
    ggplot2::ggplot(validated$summary,
      ggplot2::aes(stats::reorder(category, coordinate_pct), coordinate_pct)) +
      ggplot2::geom_col(fill = "#176b3a") + ggplot2::coord_flip() +
      ggplot2::theme_minimal() +
      ggplot2::labs(x = NULL, y = "% com coordenada valida", caption = "Denominador: registros da categoria")
  })
  output$agreement_table <- DT::renderDT({
    agreement <- if (nrow(result_state())) metric_agreement(result_state(), input$query_k) else data.frame()
    DT::datatable(agreement, rownames = FALSE,
      options = list(pageLength = 10, scrollX = TRUE))
  })

  owner_id <- substr(digest::digest(session$token), 1L, 16L)
  batch_message <- shiny::reactiveVal("")
  shiny::observeEvent(input$submit_batch, {
    shiny::req(input$batch_file)
    job <- tryCatch(submit_batch_job(input$batch_file$datapath, owner_id, list(
      k = input$query_k, radius_m = input$query_radius, modes = input$query_modes,
      directions = input$query_direction, categories = input$categories
    ), config, original_name = input$batch_file$name), error = identity)
    batch_message(if (inherits(job, "error")) conditionMessage(job) else paste("Lote enviado:", job))
  })
  output$batch_message <- shiny::renderUI(shiny::p(batch_message()))
  output$jobs_table <- DT::renderDT({
    shiny::invalidateLater(3000, session)
    jobs <- queue_list(config, owner_id)
    shown <- intersect(c("job_id", "status", "created_at", "progress_done", "progress_total", "message"), names(jobs))
    DT::datatable(jobs[, shown, drop = FALSE], rownames = FALSE, options = list(dom = "t", scrollX = TRUE))
  })
  output$download_batch <- shiny::downloadHandler(
    filename = function() paste0(slugify(input$batch_download_id %||% "lote"), ".zip"),
    content = function(file) {
      jobs <- queue_list(config, owner_id)
      selected <- jobs[jobs$job_id == input$batch_download_id & jobs$status == "completed", , drop = FALSE]
      shiny::validate(shiny::need(nrow(selected) == 1L, "Lote concluido nao encontrado nesta sessao."))
      relative <- list.files(selected$output_dir[[1]], recursive = TRUE, full.names = FALSE,
        include.dirs = FALSE)
      relative <- relative[!grepl("^(input\\.|checkpoint\\.rds$)", relative)]
      shiny::validate(shiny::need(length(relative) > 0L, "O lote ainda nao possui artefatos."))
      zip::zipr(file, files = relative, root = selected$output_dir[[1]], include_directories = FALSE)
    }
  )
}

#' Run the Sampa+Rural proximity Shiny application
#'
#' @param config Project configuration.
#' @param equipment Optional equipment data.
#' @param graphs Optional network graphs.
#' @param ... Passed to `shiny::runApp()`.
#' @export
run_app <- function(config = read_sampa_config(), equipment = NULL, graphs = NULL, ...) {
  options(sass.cache = file.path(tempdir(), "sampamaisrural-sass"))
  equipment <- equipment %||% load_equipment_data(config)
  graphs <- graphs %||% load_network_graphs(config)
  init_job_queue(config)
  www <- system.file("app", "www", package = "sampamaisrural")
  if (!nzchar(www)) www <- file.path(project_root(), "inst", "app", "www")
  shiny::addResourcePath("sampamaisrural-assets", www)
  app <- shiny::shinyApp(
    ui = app_ui(config),
    server = function(input, output, session) app_server(input, output, session, config, equipment, graphs),
    options = list(www.dir = www)
  )
  shiny::runApp(app, ...)
}
