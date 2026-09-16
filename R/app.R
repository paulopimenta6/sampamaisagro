local_table <- function(data, ..., options = list()) {
  language <- list(search = "Filtrar:", lengthMenu = "Mostrar _MENU_ linhas",
    info = "Linhas _START_ a _END_ de _TOTAL_", infoEmpty = "Nenhuma linha",
    zeroRecords = "Nenhum registro encontrado", emptyTable = "Nenhum dado para exibir",
    paginate = list(previous = "Anterior", `next` = "Pr\u00f3xima"))
  DT::datatable(data, ..., options = utils::modifyList(list(language = language), options))
}

app_ui <- function(config, available_modes = character()) {
  methodology <- system.file("app", "methodology.md", package = "sampamaisrural")
  bslib::page_navbar(title = "SampaMaisAgro", id = "main_nav", fillable = FALSE,
    theme = bslib::bs_theme(version = 5, bootswatch = "flatly", primary = "#176b3a"),
    header = shiny::tags$head(
      shiny::tags$link(rel = "stylesheet", href = "sampamaisrural-assets/app.css"),
      shiny::tags$link(rel = "icon", href = "data:,"),
      shiny::tags$meta(name = "description", content = "Agricultura e alimenta\u00e7\u00e3o perto de voc\u00ea. An\u00e1lise offline com dados oficiais.")),
    bslib::nav_panel("Explorar", value = "explore",
      bslib::layout_sidebar(fillable = FALSE, sidebar = bslib::sidebar(width = 310,
        shiny::h4("O que existe perto de voc\u00ea?"),
        shiny::radioButtons("origin_method", "Como localizar a origem?",
          c("CEP" = "cep", "Latitude e longitude" = "coordinates"), selected = "cep", inline = TRUE),
        shiny::conditionalPanel("input.origin_method == 'cep'",
          shiny::textInput("cep", "CEP", value = "05586-001"),
          shiny::helpText("CEP \u00e9 um ponto aproximado. Sem n\u00famero de im\u00f3vel, n\u00e3o \u00e9 um endere\u00e7o exato.")),
        shiny::conditionalPanel("input.origin_method == 'coordinates'",
          shiny::numericInput("latitude", "Latitude", -23.571872, min = -90, max = 90, step = 0.000001),
          shiny::numericInput("longitude", "Longitude", -46.730196, min = -180, max = 180, step = 0.000001)),
        shiny::selectizeInput("categories", "Tipos de equipamento",
          choices = stats::setNames(names(equipment_groups), equipment_groups), multiple = TRUE,
          options = list(placeholder = "Todos os tipos", plugins = list("remove_button"))),
        shiny::selectInput("accessibility", "Acessibilidade declarada",
          c("Todos (inclusive n\u00e3o informada)" = "all", "Somente informada como sim" = "yes")),
        shiny::numericInput("query_radius", "Raio de busca (metros)", config$proximity$default_radius_m, min = 1, max = 100000),
        shiny::numericInput("query_k", "M\u00ednimo de vizinhos por m\u00e9trica (k)", config$proximity$default_k, min = 1, max = 1000),
        shiny::helpText("Retemos quem est\u00e1 no raio OU entre os k mais pr\u00f3ximos. A coluna \u201cno raio\u201d distingue os dois casos."),
        shiny::checkboxGroupInput("query_modes", "Adicionar trajetos em rede",
          choices = c("A p\u00e9" = "foot", "Bicicleta" = "bicycle", "Carro" = "motorcar")[
            c("foot", "bicycle", "motorcar") %in% available_modes], selected = character()),
        shiny::helpText("As 5 dist\u00e2ncias geom\u00e9tricas s\u00e3o sempre calculadas. Rede usa vias locais e pode levar mais tempo."),
        shiny::selectInput("query_direction", "Sentido dos trajetos",
          c("Ida: origem \u2192 equipamento" = "origin_to_equipment", "Volta" = "equipment_to_origin", "Ida e volta" = "both")),
        shiny::actionButton("run_query", "Encontrar equipamentos", class = "btn-primary w-100"),
        shiny::hr(),
        shiny::downloadButton("download_results", "Resultados CSV"),
        shiny::downloadButton("download_report", "Relat\u00f3rio HTML")),
        shiny::uiOutput("data_notice"), shiny::uiOutput("query_status"), shiny::uiOutput("query_kpis"),
        bslib::card(bslib::card_header("Mapa local \u00b7 explore os pontos"),
          shiny::selectInput("map_metric", "Dist\u00e2ncia exibida", choices = c("Vis\u00e3o geral da base" = "overview")),
          leaflet::leafletOutput("proximity_map", height = "560px"),
          shiny::p(class = "small text-muted",
            "O c\u00edrculo \u00e9 uma refer\u00eancia geod\u00e9sica. Manhattan/Chebyshev n\u00e3o s\u00e3o trajetos de rua. Clique em um ponto para ver seus dados.")),
        bslib::card(bslib::card_header("Equipamentos encontrados"), DT::DTOutput("proximity_table")))),
    bslib::nav_panel("Lotes", value = "batch",
      bslib::card(bslib::card_header("V\u00e1rios lugares, uma s\u00f3 an\u00e1lise"),
        shiny::p("Envie CSV, TSV, XLSX ou Parquet: uma linha por origem. Use query_id e cep OU latitude e longitude."),
        shiny::p("Preserve os zeros do CEP como texto. Campos k e radius_m s\u00e3o opcionais por linha. Os filtros de tipos e modos da aba Explorar tamb\u00e9m se aplicam."),
        shiny::downloadButton("download_template", "Baixar exemplo de lote"),
        shiny::fileInput("batch_file", "Arquivo", accept = c(".csv", ".tsv", ".xlsx", ".xls", ".parquet")),
        shiny::actionButton("submit_batch", "Analisar lote", class = "btn-primary"),
        shiny::uiOutput("batch_message"),
        shiny::p("At\u00e9 100 origens por execu\u00e7\u00e3o na interface. Para lotes maiores use scripts/batch.R (parti\u00e7\u00f5es e retomada)."),
        DT::DTOutput("batch_errors"), shiny::downloadButton("download_batch", "Baixar pacote do lote (.zip)"))),
    bslib::nav_panel("Estat\u00edsticas", value = "statistics",
      shiny::uiOutput("statistics_notice"),
      bslib::layout_columns(
        bslib::card(bslib::card_header("Cobertura da base por tipo"), shiny::plotOutput("category_plot")),
        bslib::card(bslib::card_header("Dist\u00e2ncias da consulta"), shiny::plotOutput("distance_plot")), col_widths = c(6,6)),
      bslib::card(bslib::card_header("Resumo por origem e m\u00e9trica"), DT::DTOutput("summary_table")),
      bslib::card(bslib::card_header("Concord\u00e2ncia no subconjunto comum"), DT::DTOutput("agreement_table")),
      bslib::card(bslib::card_header("Diagn\u00f3stico das rotas antes da sele\u00e7\u00e3o"), DT::DTOutput("routing_table")),
      shiny::p("Estat\u00edstica descritiva dos registros selecionados, n\u00e3o amostra representativa da cidade. Categorias podem se sobrepor. Proximidade n\u00e3o mede pre\u00e7o, qualidade, hor\u00e1rio de funcionamento ou acesso efetivo.")),
    bslib::nav_panel("Banco offline", value = "data",
      shiny::h3("Sua despensa de dados"),
      shiny::p("O cat\u00e1logo completo, CSV e JSON ficam em data/raw. A base anal\u00edtica fica em data/processed; CEPs e mapas t\u00eam seus pr\u00f3prios diret\u00f3rios."),
      shiny::uiOutput("offline_status"),
      shiny::h4("Arquivos oficiais baixados"), DT::DTOutput("inventory_table"),
      shiny::h4("Cobertura dos tipos solicitados"), DT::DTOutput("coverage_table"),
      shiny::p("Zero registros significa aus\u00eancia no cadastro consultado, n\u00e3o prova de inexist\u00eancia na cidade. Caixas comerciais na CEAGESP n\u00e3o equivalem ao cadastro completo da central. A triagem usa o ret\u00e2ngulo de estudo da configura\u00e7\u00e3o, incluindo pontos adjacentes; o campo within_municipality identifica o limite municipal de refer\u00eancia."),
      shiny::h4("Qualidade e exclus\u00f5es"), DT::DTOutput("quality_table"), DT::DTOutput("issues_table"),
      shiny::h4("CEPs preparados para consulta sem internet"), DT::DTOutput("cep_table"),
      shiny::p("Para um novo CEP: com internet, execute Rscript scripts/prepare_ceps.R SEU_CEP. Tamb\u00e9m aceita um CSV com a coluna cep. Depois disso a consulta \u00e9 local.")),
    bslib::nav_panel("Como interpretar", value = "methodology", shiny::includeMarkdown(methodology)),
    footer = shiny::div(class = "app-footer",
      "SampaMaisAgro \u00b7 dados Sampa+Rural / Prefeitura de S\u00e3o Paulo e parceiros \u00b7 pesquisa acad\u00eamica \u00b7 execu\u00e7\u00e3o offline"))
}

proximity_summary <- function(results) {
  if (!nrow(results)) return(data.frame())
  results |>
    dplyr::group_by(origin_id, metric_label, direction) |>
    dplyr::summarise(equipamentos = dplyr::n_distinct(equipment_id),
      no_raio = sum(within_radius), minimo_m = min(distance_m),
      mediana_m = stats::median(distance_m), p90_m = as.numeric(stats::quantile(distance_m, 0.9)),
      maximo_m = max(distance_m), .groups = "drop")
}

app_server <- function(input, output, session, config, equipment, graphs, context) {
  available_modes <- if (is.null(graphs)) config$network$modes[file.exists(file.path(config$data_dir,
    "processed", paste0("network_", config$network$modes, ".rds")))] else names(graphs)
  query_graphs <- function(modes) {
    if (!length(modes)) return(list())
    if (is.null(graphs)) load_network_graphs(config, modes) else graphs[intersect(modes, names(graphs))]
  }
  validated <- validate_equipment(classify_equipment(equipment), config)
  equipment <- validated$data
  result_state <- shiny::reactiveVal(data.frame())
  origin_state <- shiny::reactiveVal(data.frame())
  selected_equipment <- shiny::reactiveVal(validated$eligible)
  status_state <- shiny::reactiveVal("A base real j\u00e1 est\u00e1 no mapa. Escolha uma origem e clique em Encontrar equipamentos.")
  result_note <- shiny::reactiveVal("Ainda n\u00e3o foi feita uma consulta; o gr\u00e1fico de cobertura descreve a base local.")
  batch_state <- shiny::reactiveVal(NULL)
  batch_message <- shiny::reactiveVal("")
  batch_errors <- shiny::reactiveVal(data.frame())
  filters <- shiny::reactive(filter_equipment(equipment, input$categories, input$accessibility))

  output$data_notice <- shiny::renderUI(shiny::div(class = "alert alert-success", role = "status",
    sprintf("Base oficial local \u00b7 %s registros \u00fanicos \u00b7 %s mape\u00e1veis \u00b7 snapshot %s",
      nrow(equipment), nrow(validated$eligible), paste(unique(equipment$snapshot_date), collapse = ", "))))
  output$query_status <- shiny::renderUI(shiny::div(class = "query-status", role = "status", status_state()))
  output$offline_status <- shiny::renderUI(shiny::div(class = "alert alert-info",
    paste("Execu\u00e7\u00e3o offline. Modos de rede instalados:", if (length(available_modes)) paste(available_modes, collapse = ", ") else "nenhum; execute scripts/prepare_network.R",
      "\u00b7 Os CEPs n\u00e3o preparados exigem uma etapa pr\u00e9via de download. Nenhum servi\u00e7o externo \u00e9 chamado ao consultar.")))

  install_result <- function(result, origins, eq, message) {
    result_state(result)
    origin_state(origins)
    selected_equipment(validate_equipment(eq, config)$eligible)
    if (nrow(result)) {
      keys <- result[!duplicated(result$metric_id), c("metric_id", "metric_label")]
      shiny::updateSelectInput(session, "map_metric",
        choices = stats::setNames(keys$metric_id, keys$metric_label), selected = keys$metric_id[[1]])
    } else shiny::updateSelectInput(session, "map_metric", choices = c("Vis\u00e3o geral da base" = "overview"))
    status_state(message)
    result_note(paste(message, "Resumos referem-se ao subconjunto retido (raio OU top-k), n\u00e3o \u00e0 cidade inteira."))
  }

  shiny::observeEvent(input$run_query, {
    result_state(data.frame()); origin_state(data.frame())
    origin <- if (input$origin_method == "cep") data.frame(query_id = "consulta-1", cep = input$cep) else
      data.frame(query_id = "consulta-1", latitude = input$latitude, longitude = input$longitude)
    origin$k <- input$query_k; origin$radius_m <- input$query_radius
    tryCatch(shiny::withProgress(message = "Analisando a base local", value = 0.2, {
      resolved <- resolve_origins(origin, config)
      if (!nrow(resolved$valid)) stop(paste(unique(resolved$errors$message), collapse = "; "))
      eq <- filters()
      result <- calculate_proximity(resolved$valid, eq, query_graphs(input$query_modes), k = input$query_k,
        radius_m = input$query_radius, modes = input$query_modes, directions = input$query_direction, config = config)
      origins <- resolved$valid
      names(origins)[names(origins) == "query_id"] <- "origin_id"
      note <- if (input$origin_method == "cep") sprintf(" CEP aproximado: %.6f, %.6f \u00b7 %s.",
        origins$latitude[1], origins$longitude[1], origins$geocode_source[1]) else " Coordenadas fornecidas."
      message <- if (nrow(result)) sprintf("Consulta conclu\u00edda: %d equipamentos distintos selecionados.%s",
        length(unique(result$equipment_id)), note) else "Nenhum equipamento mape\u00e1vel para esses filtros. Amplie os tipos ou remova o filtro de acessibilidade."
      install_result(result, origins, eq, message)
    }), error = function(e) {
      install_result(data.frame(), data.frame(), filters(), paste("Consulta n\u00e3o realizada:", conditionMessage(e)))
    })
  })

  output$query_kpis <- shiny::renderUI({
    result <- result_state()
    if (!nrow(result)) return(NULL)
    shown <- result[result$metric_id == input$map_metric, ]
    if (!nrow(shown)) return(NULL)
    shiny::div(class = "kpi-grid",
      shiny::div(class = "kpi", shiny::strong(length(unique(shown$equipment_id))), shiny::span("equipamentos selecionados")),
      shiny::div(class = "kpi", shiny::strong(sum(shown$within_radius)), shiny::span("pares origem/equipamento no raio")),
      shiny::div(class = "kpi", shiny::strong(sprintf("%.0f m", min(shown$distance_m))), shiny::span("menor dist\u00e2ncia")))
  })
  output$proximity_map <- leaflet::renderLeaflet({
    make_leaflet_map(result_state(), origin_state(), input$map_metric,
      equipment = selected_equipment(), context = context,
      radius_m = if (nrow(origin_state()) == 1L) origin_state()$radius_m else NULL)
  })
  output$proximity_table <- DT::renderDT({
    result <- result_state()
    if (!nrow(result)) return(DT::datatable(data.frame(Aviso = "Os equipamentos aparecer\u00e3o aqui ap\u00f3s uma consulta v\u00e1lida."), rownames = FALSE))
    shown <- result[result$metric_id == input$map_metric, , drop = FALSE]
    fields <- intersect(c("origin_id", "equipment_name", "primary_group", "address", "accessibility",
      "rank", "distance_m", "duration_min", "within_radius", "direction", "routing_status"), names(shown))
    labels <- c(origin_id = "Origem", equipment_name = "Equipamento", primary_group = "Tipo",
      address = "Endere\u00e7o", accessibility = "Acessibilidade", rank = "Posi\u00e7\u00e3o", distance_m = "Dist\u00e2ncia (m)",
      duration_min = "Tempo (min)", within_radius = "No raio?", direction = "Sentido", routing_status = "Situa\u00e7\u00e3o da rota")
    shown$within_radius <- ifelse(shown$within_radius, "Sim", "N\u00e3o")
    table <- local_table(shown[, fields, drop = FALSE], rownames = FALSE, filter = "top", colnames = unname(labels[fields]),
      options = list(pageLength = 10, scrollX = TRUE))
    DT::formatRound(table, which(fields %in% c("distance_m", "duration_min")), 1)
  })
  output$download_results <- shiny::downloadHandler(
    filename = function() paste0("proximidade-", Sys.Date(), ".csv"),
    content = function(file) { shiny::req(nrow(result_state()) > 0); readr::write_csv(result_state(), file, na = "") })
  output$download_report <- shiny::downloadHandler(
    filename = function() paste0("relatorio-", Sys.Date(), ".html"),
    content = function(file) {
      shiny::req(nrow(result_state()) > 0)
      render_proximity_report(result_state(), file, origin_state(), selected_equipment(), config)
    })
  output$statistics_notice <- shiny::renderUI(shiny::p(class = "query-status", result_note()))
  output$category_plot <- shiny::renderPlot({
    coverage <- group_coverage(equipment, config)
    ggplot2::ggplot(coverage, ggplot2::aes(stats::reorder(grupo, mapeaveis), mapeaveis)) +
      ggplot2::geom_col(fill = "#176b3a") + ggplot2::coord_flip() + ggplot2::theme_minimal() +
      ggplot2::labs(x = NULL, y = "Registros mape\u00e1veis", caption = "Grupos se sobrep\u00f5em; n\u00e3o some as barras.")
  })
  output$distance_plot <- shiny::renderPlot({
    result <- result_state()
    shiny::validate(shiny::need(nrow(result) > 0, "Fa\u00e7a uma consulta para gerar este gr\u00e1fico."))
    shown <- result[result$metric_id == input$map_metric, ]
    ggplot2::ggplot(shown, ggplot2::aes(distance_m / 1000)) +
      ggplot2::geom_histogram(bins = 25, fill = "#2c7380", colour = "white") +
      ggplot2::theme_minimal() + ggplot2::labs(x = "Dist\u00e2ncia (km)", y = "Pares selecionados",
        caption = "Subconjunto: dentro do raio OU top-k, para a m\u00e9trica exibida no mapa.")
  })
  output$summary_table <- DT::renderDT(DT::datatable(proximity_summary(result_state()),
    rownames = FALSE, options = list(scrollX = TRUE)))
  output$agreement_table <- DT::renderDT({
    x <- if (nrow(result_state())) metric_agreement(result_state(), input$query_k) else data.frame()
    DT::datatable(x, rownames = FALSE, options = list(scrollX = TRUE, pageLength = 10))
  })
  output$quality_table <- DT::renderDT(DT::datatable(validated$summary, rownames = FALSE))
  output$routing_table <- DT::renderDT({
    x <- attr(result_state(), "routing_diagnostics")
    if (is.null(x)) x <- data.frame()
    if (nrow(x)) x <- x[grepl("^network_", x$metric_id), , drop = FALSE]
    local_table(x, rownames = FALSE, options = list(scrollX = TRUE))
  })
  output$issues_table <- DT::renderDT(DT::datatable(validated$issues, rownames = FALSE))
  output$coverage_table <- DT::renderDT(DT::datatable(group_coverage(equipment, config), rownames = FALSE))
  output$inventory_table <- DT::renderDT({
    x <- local_inventory(config)
    fields <- intersect(c("dataset", "format", "records", "bytes", "sha256", "path"), names(x))
    DT::datatable(x[, fields, drop = FALSE], rownames = FALSE, options = list(scrollX = TRUE, pageLength = 15))
  })
  output$cep_table <- DT::renderDT({
    paths <- list.files(file.path(config$data_dir, "cache", "cep"), pattern = "\\.rds$", full.names = TRUE)
    x <- dplyr::bind_rows(lapply(paths, function(p) {
      z <- readRDS(p)
      if (identical(attr(z, "cache_schema"), 2L)) z else NULL
    }))
    DT::datatable(x, rownames = FALSE, options = list(scrollX = TRUE))
  })
  output$download_template <- shiny::downloadHandler(filename = function() "exemplo-lote.csv",
    content = function(file) readr::write_csv(data.frame(query_id = c("cep-teste", "praca"),
      cep = c("05586001", NA), latitude = c(NA, -23.55008), longitude = c(NA, -46.63408)), file, na = ""))
  shiny::observeEvent(input$submit_batch, {
    shiny::req(input$batch_file)
    batch_errors(data.frame()); batch_state(NULL)
    result_state(data.frame()); origin_state(data.frame())
    tryCatch(shiny::withProgress(message = "Analisando lote local", value = 0.1, {
      job_dir <- file.path(config$jobs_dir, new_job_id())
      dir.create(job_dir, recursive = TRUE)
      path <- file.path(job_dir, paste0("input.", tolower(tools::file_ext(input$batch_file$name))))
      if (!file.copy(input$batch_file$datapath, path)) stop("N\u00e3o foi poss\u00edvel guardar o arquivo.")
      raw <- read_origin_file(path)
      if (!nrow(raw)) stop("O arquivo n\u00e3o cont\u00e9m origens.")
      if (nrow(raw) > 100) stop("Na interface, envie at\u00e9 100 origens. Use scripts/batch.R para lotes maiores.")
      eq <- filters()
      batch_cfg <- config
      batch_cfg$proximity$default_k <- input$query_k
      batch_cfg$proximity$default_radius_m <- input$query_radius
      batch_cfg$batch$chunk_size <- 10L
      outcome <- process_batch(raw, job_dir, eq, query_graphs(input$query_modes), batch_cfg,
        parameters = list(modes = input$query_modes, directions = input$query_direction),
        progress_callback = function(done, total, message) shiny::setProgress(value = done / total, detail = message))
      parts <- list.files(outcome$summary$partition_dir, pattern = "\\.parquet$", full.names = TRUE)
      result <- dplyr::bind_rows(lapply(parts, function(p) as.data.frame(arrow::read_parquet(p))))
      origins <- if (nrow(result)) unique(data.frame(origin_id = result$origin_id,
        longitude = result$origin_longitude, latitude = result$origin_latitude)) else data.frame()
      note <- sprintf("Lote conclu\u00eddo: %d origens v\u00e1lidas; %d com erro. Veja mapa e tabelas em Explorar e Estat\u00edsticas.",
        outcome$summary$valid_rows, outcome$summary$error_rows)
      readr::write_csv(result, file.path(job_dir, "results.csv"), na = "")
      readr::write_csv(proximity_summary(result), file.path(job_dir, "statistics.csv"), na = "")
      batch_state(outcome); batch_errors(outcome$errors); batch_message(note)
      install_result(result, origins, eq, note)
    }), error = function(e) batch_message(paste("Lote n\u00e3o realizado:", conditionMessage(e))))
  })
  output$batch_message <- shiny::renderUI(shiny::p(class = "query-status", batch_message()))
  output$batch_errors <- DT::renderDT(DT::datatable(batch_errors(), rownames = FALSE))
  output$download_batch <- shiny::downloadHandler(filename = function() "lote-sampamaisagro.zip",
    content = function(file) {
      outcome <- batch_state(); shiny::req(!is.null(outcome))
      paths <- list.files(outcome$output_dir, recursive = TRUE)
      paths <- paths[!grepl("^(input\\.|checkpoint\\.rds$|run_identity\\.rds$)", paths)]
      zip::zipr(file, files = paths, root = outcome$output_dir, include_directories = FALSE)
    })
}

#' Construct the offline Shiny application
#' @param config Project configuration.
#' @param equipment Optional equipment data.
#' @param graphs Optional network graphs.
#' @return A shiny.appobj, usable with shiny::runApp or RStudio.
#' @export
create_app <- function(config = read_sampa_config(), equipment = NULL, graphs = NULL) {
  options(sass.cache = file.path(tempdir(), "sampamaisrural-sass"))
  equipment <- equipment %||% load_equipment_data(config, allow_demo = FALSE)
  available_modes <- if (is.null(graphs)) config$network$modes[file.exists(file.path(config$data_dir,
    "processed", paste0("network_", config$network$modes, ".rds")))] else names(graphs)
  ensure_project_dirs(config)
  www <- system.file("app", "www", package = "sampamaisrural")
  shiny::addResourcePath("sampamaisrural-assets", www)
  context <- load_map_context(config)
  shiny::shinyApp(app_ui(config, available_modes), function(input, output, session) {
    app_server(input, output, session, config, equipment, graphs, context)
  })
}

#' Run the offline SampaMaisAgro Shiny application
#' @param config Project configuration.
#' @param equipment Optional equipment data.
#' @param graphs Optional network graphs.
#' @param ... Passed to shiny::runApp.
#' @export
run_app <- function(config = read_sampa_config(), equipment = NULL, graphs = NULL, ...) {
  shiny::runApp(create_app(config, equipment, graphs), ...)
}
