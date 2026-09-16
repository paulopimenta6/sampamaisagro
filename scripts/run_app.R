#!/usr/bin/env Rscript
root <- normalizePath(if (file.exists("DESCRIPTION")) "." else "..", mustWork = TRUE)
pkgload::load_all(root, quiet = TRUE)
run_app(launch.browser = interactive())
