perform_request <- function(url, config, etag = NULL) {
  req <- httr2::request(url) |>
    httr2::req_user_agent(config$user_agent) |>
    httr2::req_timeout(120) |>
    httr2::req_retry(max_tries = config$collection$max_tries %||% 4)
  if (!is.null(etag) && nzchar(etag)) req <- httr2::req_headers(req, `If-None-Match` = etag)
  httr2::req_perform(req)
}

response_headers_selected <- function(response) {
  headers <- httr2::resp_headers(response)
  keep <- intersect(names(headers), c("etag", "last-modified", "content-type", "content-length", "date"))
  as.list(headers[keep])
}

download_versioned_file <- function(url, destination, config) {
  etag_path <- paste0(destination, ".etag")
  old_etag <- if (file.exists(etag_path)) trimws(readLines(etag_path, warn = FALSE)[1]) else NULL
  response <- perform_request(url, config, old_etag)
  status <- httr2::resp_status(response)
  if (status == 304L && file.exists(destination)) {
    return(list(path = destination, status = 304L, sha256 = sha256_file(destination),
      bytes = file.info(destination)$size, headers = response_headers_selected(response)))
  }
  httr2::resp_check_status(response)
  dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
  raw <- httr2::resp_body_raw(response)
  temporary <- tempfile(pattern = ".download-", tmpdir = dirname(destination))
  on.exit(unlink(temporary), add = TRUE)
  con <- file(temporary, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(raw, con)
  close(con)
  if (!file.rename(temporary, destination)) stop("Falha ao promover download atomico: ", destination)
  on.exit(NULL, add = FALSE)
  new_etag <- httr2::resp_header(response, "etag")
  if (!is.null(new_etag)) writeLines(new_etag, etag_path, useBytes = TRUE)
  list(path = destination, status = status, sha256 = sha256_file(destination),
    bytes = length(raw), headers = response_headers_selected(response))
}

#' Collect and version the official Sampa+Rural open data
#'
#' @param config Project configuration.
#' @param snapshot_date ISO date used for the immutable snapshot directory.
#' @param formats Any of `json` and `csv`.
#' @param include_terms Whether to archive the public terms page.
#' @return A manifest data frame, invisibly.
#' @export
collect_sampa_data <- function(config = read_sampa_config(), snapshot_date = as.character(Sys.Date()),
                               formats = c("json", "csv"), include_terms = TRUE) {
  if (!isTRUE(config$collection$authorized)) {
    stop("Coleta bloqueada: registre a autorizacao em config.yml antes de executar.")
  }
  if (grepl("example\\.org", config$user_agent, ignore.case = TRUE)) {
    stop("Substitua o contato de exemplo no user_agent antes de coletar.")
  }
  ensure_project_dirs(config)
  snapshot_dir <- file.path(config$data_dir, "raw", snapshot_date)
  dir.create(snapshot_dir, recursive = TRUE, showWarnings = FALSE)

  catalog_path <- file.path(snapshot_dir, "data_reports.json")
  catalog_download <- download_versioned_file(config$catalog_url, catalog_path, config)
  catalog <- jsonlite::fromJSON(catalog_path, simplifyVector = FALSE)
  if (!is.list(catalog) || !length(catalog)) stop("Catalogo vazio ou em formato inesperado.")

  rows <- list(list(
    dataset = "catalog", format = "json", url = config$catalog_url,
    path = catalog_download$path, status = catalog_download$status,
    sha256 = catalog_download$sha256, bytes = catalog_download$bytes,
    extracted_at = utc_now(), headers = jsonlite::toJSON(catalog_download$headers, auto_unbox = TRUE)
  ))

  delay <- 1 / max(as.numeric(config$collection$requests_per_second %||% 1), 0.01)
  idx <- 1L
  for (report in catalog) {
    for (fmt in intersect(formats, c("json", "csv"))) {
      url <- report[[fmt]]
      if (is.null(url) || !nzchar(url)) next
      Sys.sleep(delay)
      idx <- idx + 1L
      extension <- paste0(".", fmt)
      filename <- paste0(slugify(report$name), extension)
      result <- download_versioned_file(url, file.path(snapshot_dir, filename), config)
      rows[[idx]] <- list(
        dataset = report$name, format = fmt, url = url, path = result$path,
        status = result$status, sha256 = result$sha256, bytes = result$bytes,
        extracted_at = utc_now(), headers = jsonlite::toJSON(result$headers, auto_unbox = TRUE)
      )
    }
  }

  if (isTRUE(include_terms)) {
    Sys.sleep(delay)
    idx <- idx + 1L
    result <- download_versioned_file(config$terms_url, file.path(snapshot_dir, "termos.html"), config)
    rows[[idx]] <- list(dataset = "terms", format = "html", url = config$terms_url,
      path = result$path, status = result$status, sha256 = result$sha256, bytes = result$bytes,
      extracted_at = utc_now(), headers = jsonlite::toJSON(result$headers, auto_unbox = TRUE))
  }

  manifest <- dplyr::bind_rows(rows)
  readr::write_csv(manifest, file.path(snapshot_dir, "manifest.csv"))
  atomic_write_json(list(snapshot_date = snapshot_date, package_version = "0.1.0",
    source_credit = "Sampa+Rural e parceiros", files = rows), file.path(snapshot_dir, "manifest.json"))
  invisible(manifest)
}
