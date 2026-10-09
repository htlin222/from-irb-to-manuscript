# 產生 Word／HTML、讀 Word 文字、雙盲檢查用詞：build.R（投稿）與 build_revision.R（修訂）共用。
# 需要先定義 BUILD（輸出資料夾）與 cfg、cv（config.toml、cv.toml）。

run <- function(cmd, args, ...) {
  st <- system2(cmd, args, ...)
  if (!identical(st, 0L) && !is.null(st) && st != 0) stop(cmd, " 失敗（", st, "）")
}

# env：傳給 quarto 的環境變數（例如 MS_TEXT_DIR、MS_RESPONSE，見 render_helpers.R）
render <- function(qmd, out, to = "docx", env = character(), dest = BUILD) {
  log <- file.path(BUILD, paste0(qmd, ".log"))
  # Word：--output 相對於執行目錄（專案根目錄）；HTML 自包含檔要在原位置產生，否則找不到 quarto 的元件
  produced <- if (to == "html") file.path("manuscript", out) else out
  argv <- c("render", file.path("manuscript", qmd), "--to", to, if (to != "html") c("--output", out))
  # 環境變數的值經 shell 解讀，要加引號（值可含空白、括號）
  env <- vapply(strsplit(env, "=", fixed = TRUE), function(kv) paste0(kv[1], "=", shQuote(paste(kv[-1], collapse = "="))), "")
  st <- system2("quarto", argv, stdout = log, stderr = log, env = env)
  if (st != 0 || !file.exists(produced)) stop(qmd, " 產生失敗，請看 ", log)
  invisible(file.rename(produced, file.path(dest, out)))
}

docx_text <- function(f) {
  x <- system2("unzip", c("-p", f, "word/document.xml"), stdout = TRUE)
  gsub("<[^>]+>", " ", paste(x, collapse = " "))
}

blind_terms_for <- function(cfg, cv) {
  people <- c(list(cv$pi), cv$co_pi)
  inst <- RcppTOML::parseTOML(file.path("institutions", cfg$institution, "profile.toml"))
  unique(Filter(nzchar, c(
    vapply(people, `[[`, "", "name"), vapply(people, `[[`, "", "name_en"),
    vapply(people, function(p) p$email %||% "", ""), cfg$study$irb_no,
    unlist(inst[c("name", "name_en", "short_name", "heading")]), "KFSYSCC", "Koo Foundation")))
}

# Word → PDF（LibreOffice）→ 每頁的文字行；找不到 LibreOffice 時回傳 NULL
SOFFICE <- "/Applications/LibreOffice.app/Contents/MacOS/soffice"
pdf_page_lines <- function(docx) {
  if (!file.exists(SOFFICE)) return(NULL)
  out_dir <- file.path(tempdir(), "jcrp_pdf"); dir.create(out_dir, showWarnings = FALSE)
  system2(SOFFICE, c(paste0("-env:UserInstallation=file://", file.path(tempdir(), "lo-profile")), "--headless",
                     "--convert-to", "pdf", "--outdir", out_dir, docx), stdout = FALSE, stderr = FALSE)
  pdf <- file.path(out_dir, sub("\\.docx$", ".pdf", basename(docx)))
  info <- suppressWarnings(system2("pdfinfo", pdf, stdout = TRUE))
  n <- as.integer(sub("^Pages:\\s+", "", grep("^Pages:", info, value = TRUE)))
  lapply(seq_len(n), function(i) trimws(system2("pdftotext", c("-f", i, "-l", i, pdf, "-"), stdout = TRUE)))
}
