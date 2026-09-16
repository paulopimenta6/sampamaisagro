#!/usr/bin/env Rscript
pkgload::load_all(".", quiet = TRUE)
args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) args <- c("05586001", "01001000")
if (length(args) == 1 && file.exists(args)) {
  input <- sampamaisrural:::read_origin_file(args)
  if (!"cep" %in% names(input)) stop("Arquivo precisa ter a coluna cep.")
  args <- unique(stats::na.omit(input$cep))
}
cfg <- read_sampa_config(overrides = list(geocoding = list(offline = FALSE)))
for (cep in args) {
  result <- tryCatch(geocode_cep(cep, cfg), error = function(e) e)
  if (inherits(result, "error")) message(cep, ": ", conditionMessage(result)) else print(result)
  Sys.sleep(1)
}
