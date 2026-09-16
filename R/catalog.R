# Rules are inspectable: labels are not certifications or opening-hours guarantees.
equipment_groups <- c(
  feiras_livres = "Feiras livres", feiras_organicas = "Feiras org\u00e2nicas",
  hortifruti = "Hortifrutis e sacol\u00f5es", abastecimento = "Abastecimento / CEASA / CEAGESP",
  organicos = "Alimentos e com\u00e9rcio de org\u00e2nicos", hortas = "Hortas urbanas e institucionais",
  agricultores = "Agricultores e produ\u00e7\u00e3o rural", alimentacao = "Com\u00e9rcio e alimenta\u00e7\u00e3o",
  apoio = "Apoio \u00e0 agricultura e pol\u00edticas p\u00fablicas", conexoes = "Viv\u00eancia rural e aldeias",
  outros = "Outros registros da fonte"
)

classify_equipment <- function(data) {
  for (field in c("subcategory", "qualifications", "accessibility_reported")) {
    if (!field %in% names(data)) data[[field]] <- rep(NA_character_, nrow(data))
  }
  clean <- function(x) tolower(iconv(ifelse(is.na(x), "", x), to = "ASCII//TRANSLIT"))
  text <- clean(paste(data$equipment_name, data$category, data$subcategory, data$qualifications))
  patterns <- c(feiras_livres = "feiras? livres?", feiras_organicas = "feiras? organicas?",
    hortifruti = "hortifr|sacol[a-z]*", abastecimento = "ceasa|ceagesp|abastecimento",
    organicos = "organic", hortas = "hortas?", agricultores = "agricultores?|produtor|producao",
    alimentacao = "alimentacao|restaurantes?|mercados|comercio|consumo responsavel|doacao",
    apoio = "iniciativas|politicas publicas|servicos para agricultura|pesquisa|extensao|cooperativas|associacoes",
    conexoes = "vivencia rural|aldeias|ecoturismo")
  if (!nrow(data)) {
    data$groups <- data$primary_group <- data$accessibility <- character()
    return(data)
  }
  hits <- vapply(patterns, function(pattern) grepl(pattern, text), logical(nrow(data)))
  hits <- matrix(hits, nrow = nrow(data), dimnames = list(NULL, names(patterns)))
  data$groups <- apply(hits, 1, function(row) {
    found <- names(patterns)[row]
    if (length(found)) paste(found, collapse = "|") else "outros"
  })
  data$primary_group <- unname(equipment_groups[sub("\\|.*$", "", data$groups)])
  acc <- clean(data$accessibility_reported)
  data$accessibility <- ifelse(acc %in% c("true", "sim", "1"), "Informada: sim",
    ifelse(acc %in% c("false", "nao", "0"), "Informada: n\u00e3o", "N\u00e3o informada"))
  data
}

filter_equipment <- function(equipment, groups = NULL, accessibility = "all") {
  equipment <- classify_equipment(equipment)
  if (length(groups)) {
    equipment <- equipment[vapply(strsplit(equipment$groups, "|", fixed = TRUE),
      function(x) any(x %in% groups), logical(1)), , drop = FALSE]
  }
  if (identical(accessibility, "yes")) equipment <- equipment[equipment$accessibility == "Informada: sim", , drop = FALSE]
  equipment
}

group_coverage <- function(equipment, config = read_sampa_config()) {
  equipment <- classify_equipment(equipment)
  eligible <- validate_equipment(equipment, config)$eligible$equipment_id
  dplyr::bind_rows(lapply(names(equipment_groups), function(group) {
    rows <- filter_equipment(equipment, group)
    data.frame(grupo = unname(equipment_groups[[group]]), registros = nrow(rows),
      mapeaveis = sum(rows$equipment_id %in% eligible),
      acessibilidade_sim = sum(rows$accessibility == "Informada: sim"))
  }))
}

local_inventory <- function(config = read_sampa_config()) {
  path <- file.path(config$data_dir, "processed", "inventory.csv")
  if (!file.exists(path)) return(data.frame())
  as.data.frame(readr::read_csv(path, show_col_types = FALSE))
}

#' Build the local analytical database from a completed download
#' @param manifest Manifest returned by `collect_sampa_data()`.
#' @param config Project configuration.
#' @return Validated, classified equipment data invisibly.
#' @export
prepare_equipment_data <- function(manifest, config = read_sampa_config()) {
  json_files <- manifest$path[manifest$format == "json" & !manifest$dataset %in% c("catalog", "terms")]
  base <- json_files[grepl("base-completa", basename(json_files))]
  if (length(base) != 1) stop("E necessario exatamente um relatorio base completa.")
  paths <- c(base, setdiff(json_files, base))
  all <- lapply(paths, function(path) {
    records <- normalize_sampa_json(path)
    records$source_report <- rep(basename(path), nrow(records))
    records
  })
  data <- dplyr::bind_rows(all)
  membership <- tapply(data$source_report, data$source_key, function(x) paste(unique(x), collapse = " | "))
  # The complete report is authoritative. Subreports omit columns, and their
  # different payload hashes must not duplicate the same baseline profiles.
  baseline <- all[[1]]
  additional <- data[!data$source_key %in% baseline$source_key, , drop = FALSE]
  additional <- additional[!duplicated(additional$source_key), , drop = FALSE]
  data <- dplyr::bind_rows(baseline[!duplicated(baseline$equipment_id), , drop = FALSE], additional)
  data$source_reports <- as.character(membership[data$source_key])
  reconciliation <- data.frame(report = basename(paths), rows = vapply(all, nrow, integer(1)),
    absent_from_complete = vapply(all, function(x) sum(!x$source_key %in% baseline$source_key), integer(1)))
  checked <- validate_equipment(classify_equipment(data), config)
  public <- checked$data[, setdiff(names(checked$data), c("source_payload", "description")), drop = FALSE]
  target <- file.path(config$data_dir, "processed")
  dir.create(target, recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(reconciliation, file.path(target, "source_reconciliation.csv"))
  atomic_write_json(list(raw_complete_records = nrow(baseline),
    exact_duplicates_removed = sum(duplicated(baseline$equipment_id)),
    additional_from_subreports = nrow(additional), analytical_records = nrow(data)),
    file.path(target, "deduplication.json"))
  arrow::write_parquet(public, file.path(target, "equipment.parquet"))
  readr::write_csv(public, file.path(target, "equipment.csv"), na = "")
  atomic_write_json(public, file.path(target, "equipment.json"))
  readr::write_csv(checked$summary, file.path(target, "data_quality_by_category.csv"))
  readr::write_csv(checked$issues, file.path(target, "data_quality_issues.csv"))
  readr::write_csv(group_coverage(public, config), file.path(target, "group_coverage.csv"))
  readr::write_csv(manifest, file.path(target, "inventory.csv"))
  atomic_save_rds(public, file.path(target, "equipment.rds"))
  message("Base local pronta: ", nrow(public), " registros \u00fanicos; ", nrow(checked$eligible), " mape\u00e1veis.")
  invisible(public)
}

#' Audit or recover a fully downloaded snapshot without network access
#' @param snapshot_dir Directory containing the catalog and its CSV/JSON reports.
#' @param config Project configuration.
#' @return Manifest with checksums, local modification times and row counts.
#' @export
audit_local_snapshot <- function(snapshot_dir, config = read_sampa_config()) {
  catalog_path <- file.path(snapshot_dir, "data_reports.json")
  catalog <- jsonlite::fromJSON(catalog_path, simplifyVector = FALSE)
  sources <- c(list(list(name = "catalog", json = config$catalog_url)), catalog)
  rows <- list()
  for (source in sources) for (fmt in c("json", "csv")) {
    if (is.null(source[[fmt]])) next
    path <- if (source$name == "catalog") catalog_path else file.path(snapshot_dir, basename(source[[fmt]]))
    if (!file.exists(path)) stop("Snapshot incompleto: ", path)
    n <- if (source$name == "catalog") length(catalog) else if (fmt == "json") {
      body <- jsonlite::fromJSON(path, simplifyVector = FALSE)
      if (!is.list(body$partners)) stop("JSON inv\u00e1lido: ", path)
      length(body$partners)
    } else nrow(readr::read_delim(path, delim = ";", col_types = readr::cols(.default = "c"),
      show_col_types = FALSE, progress = FALSE))
    rows[[length(rows) + 1L]] <- data.frame(dataset = source$name, format = fmt, url = source[[fmt]],
      path = normalizePath(path), sha256 = sha256_file(path), bytes = file.info(path)$size,
      records = n, extracted_at = format(file.info(path)$mtime, tz = "UTC", usetz = TRUE),
      timestamp_basis = "local_file_mtime", audited_at = utc_now())
  }
  manifest <- dplyr::bind_rows(rows)
  pairs <- split(manifest[manifest$dataset != "catalog", ], manifest$dataset[manifest$dataset != "catalog"])
  if (any(vapply(pairs, function(x) nrow(x) != 2L || length(unique(x$records)) != 1L, logical(1)))) {
    stop("Relat\u00f3rios CSV/JSON ausentes ou com contagens divergentes.")
  }
  if (!file.exists(file.path(snapshot_dir, "manifest.json"))) {
    readr::write_csv(manifest, file.path(snapshot_dir, "manifest.csv"))
    atomic_write_json(list(snapshot_date = basename(snapshot_dir), recovered_by_audit = TRUE,
      files = manifest), file.path(snapshot_dir, "manifest.json"))
  }
  manifest
}
