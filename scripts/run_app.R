#!/usr/bin/env Rscript
root <- normalizePath(if (file.exists("DESCRIPTION")) "." else "..", mustWork = TRUE)
if (requireNamespace("sampamaisrural", quietly = TRUE)) library(sampamaisrural) else pkgload::load_all(root, quiet = TRUE)
run_app(launch.browser = interactive())
