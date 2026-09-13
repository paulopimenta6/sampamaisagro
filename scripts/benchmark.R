#!/usr/bin/env Rscript
root <- normalizePath(if (file.exists("DESCRIPTION")) "." else "..", mustWork = TRUE)
if (requireNamespace("sampamaisrural", quietly = TRUE)) library(sampamaisrural) else pkgload::load_all(root, quiet = TRUE)
config <- read_sampa_config(file.path(root, "config.yml"))
equipment <- load_equipment_data(config)
sizes <- c(1L, 10L, 100L, 1000L)
rows <- lapply(sizes, function(n) {
  origins <- data.frame(
    query_id = sprintf("b%06d", seq_len(n)),
    latitude = rep(-23.5505, n), longitude = rep(-46.6333, n),
    k = 10L, radius_m = 5000
  )
  elapsed <- system.time(process_batch(origins, tempfile(pattern = paste0("bench-", n, "-")),
    equipment, graphs = list(), config = config, parameters = list(k = 10L, radius_m = 5000)))
  data.frame(origins = n, elapsed_s = unname(elapsed[["elapsed"]]),
    origins_per_second = n / unname(elapsed[["elapsed"]]))
})
print(dplyr::bind_rows(rows))
