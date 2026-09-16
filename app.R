if (!requireNamespace("pkgload", quietly = TRUE)) stop("Instale pkgload para executar o projeto fonte.")
pkgload::load_all(".", quiet = TRUE)
sampamaisrural::create_app()
