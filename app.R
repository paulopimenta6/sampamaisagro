if (!requireNamespace("sampamaisrural", quietly = TRUE)) {
  if (!requireNamespace("pkgload", quietly = TRUE)) stop("Instale o pacote ou pkgload.")
  pkgload::load_all(".")
}
sampamaisrural::run_app()
