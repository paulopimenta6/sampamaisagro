#!/usr/bin/env Rscript
# Full setup is the ONLY workflow that deliberately uses external services.
pkgload::load_all(".", quiet = TRUE)
cfg <- read_sampa_config()
if (!file.exists(file.path(cfg$data_dir, "processed", "equipment.rds"))) {
  prepare_equipment_data(collect_sampa_data(cfg, include_terms = FALSE), cfg)
} else message("Base local existente preservada. Para atualizar: scripts/update_data.R.")
cfg$geocoding$offline <- FALSE
for (cep in c("05586001", "01001000")) {
  geocode_cep(cep, cfg)
  Sys.sleep(1)
}
if (!file.exists(file.path(cfg$data_dir, "processed", "network_manifest.json"))) {
  prepare_offline_maps(cfg)
} else message("Mapas/rede locais existentes preservados.")
message("Preparação concluída. A aplicação pode ser executada sem internet.")
