#' Render a reproducible proximity report
#'
#' @param results Proximity results.
#' @param output_file Target `.html` or `.pdf` file.
#' @param origins Optional resolved origins.
#' @param equipment Optional canonical data for quality summaries.
#' @param config Project configuration.
#' @return Normalized output path, invisibly.
#' @export
render_proximity_report <- function(results, output_file, origins = NULL, equipment = NULL,
                                    config = read_sampa_config()) {
  if (!requireNamespace("rmarkdown", quietly = TRUE)) stop("O pacote rmarkdown e necessario.")
  extension <- tolower(tools::file_ext(output_file))
  if (!extension %in% c("html", "pdf")) stop("output_file deve terminar em .html ou .pdf.")
  template <- system.file("reports", "proximity_report.Rmd", package = "sampamaisrural")
  if (!nzchar(template)) template <- file.path(project_root(), "inst", "reports", "proximity_report.Rmd")
  if (!file.exists(template)) stop("Template de relatorio nao encontrado.")
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  format <- if (extension == "pdf") "pdf_document" else "html_document"
  rendered <- rmarkdown::render(
    input = template, output_format = format,
    output_file = basename(output_file), output_dir = dirname(output_file),
    params = list(results = results, origins = origins, equipment = equipment, config = config),
    envir = new.env(parent = globalenv()), quiet = TRUE
  )
  invisible(normalizePath(rendered, mustWork = TRUE))
}
