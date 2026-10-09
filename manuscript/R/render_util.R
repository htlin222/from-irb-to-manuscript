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
