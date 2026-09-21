#' Render a reproducible proximity report
#'
#' @param results Proximity results.
#' @param output_file Target `.html` or `.pdf` file.
#' @param origins Optional resolved origins.
#' @param equipment Optional full inventory for quality summaries, after query
#'   filters but before spatial eligibility exclusions.
#' @param config Project configuration.
#' @param quality_context Optional list frozen at query submission, with `groups`,
#'   `accessibility`, `global_n`, and `snapshot`. Without it, quality describes
#'   only the supplied inventory, with no claim of global coverage.
#' @return Normalized output path, invisibly.
#' @export
render_proximity_report <- function(results, output_file, origins = NULL, equipment = NULL,
                                    config = read_sampa_config(), quality_context = NULL) {
  if (!requireNamespace("rmarkdown", quietly = TRUE)) stop("O pacote rmarkdown e necessario.")
  if (!nrow(results)) stop("Fa\u00e7a uma consulta com resultados antes de gerar o relat\u00f3rio.")
  extension <- tolower(tools::file_ext(output_file))
  if (!extension %in% c("html", "pdf")) stop("output_file deve terminar em .html ou .pdf.")
  template <- system.file("reports", "proximity_report.Rmd", package = "sampamaisrural")
  if (!nzchar(template)) template <- file.path(project_root(), "inst", "reports", "proximity_report.Rmd")
  if (!file.exists(template)) stop("Template de relatorio nao encontrado.")
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  intermediate <- tempfile("sampa-report-")
  dir.create(intermediate)
  on.exit(unlink(intermediate, recursive = TRUE), add = TRUE)
  format <- if (extension == "pdf") "pdf_document" else "html_document"
  rendered <- rmarkdown::render(
    input = template, output_format = format,
    output_file = basename(output_file), output_dir = dirname(output_file),
    intermediates_dir = intermediate, knit_root_dir = config$project_root,
    params = list(results = results, origins = origins, equipment = equipment, config = config,
      quality_context = quality_context),
    envir = new.env(parent = asNamespace("sampamaisrural")), quiet = TRUE
  )
  invisible(normalizePath(rendered, mustWork = TRUE))
}
