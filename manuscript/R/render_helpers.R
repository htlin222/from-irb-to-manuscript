# 各投稿文件（正文、補充資料、cover letter、STROBE 檢核表）共用的排版工具。由 .qmd source。
source("manuscript/R/tables.R")   # tokens.R、common.R
tk <- manuscript_tokens()
cfg <- RcppTOML::parseTOML("config.toml")
cv <- RcppTOML::parseTOML("cv.toml")
meta <- yaml::read_yaml("manuscript/meta.yaml")

# 讀 manuscript/text/<name>.md：去掉作者註解、填入數字代號
# MS_TEXT_DIR：修訂時改讀「標示修改處」的版本（manuscript/_build/revision/marked，已填好數字）
TEXT_DIR <- Sys.getenv("MS_TEXT_DIR", "manuscript/text")
section <- function(name) section_file(file.path(TEXT_DIR, paste0(name, ".md")))
section_file <- function(path) {
  x <- paste(readLines(path, encoding = "UTF-8"), collapse = "\n")
  x <- gsub("<!--.*?-->", "", x)           # 作者註解不輸出
  knitr::asis_output(paste0("\n", fill_tokens(x, tk), "\n"))
}
# 修訂稿標示版：表格中本輪新增的欄位與修改的註腳（manuscript/revision.yaml 的 other_changes；build_revision.R 經
# 環境變數 MS_TABLE_MARKS 傳入）以與正文相同的「Inserted Text」格式（藍色底線）標示
INSERTED_RGB <- "#1F5FBF"
table_marks <- function(t) {
  f <- Sys.getenv("MS_TABLE_MARKS")
  if (!nzchar(f)) return(list())
  Find(function(m) startsWith(t$title, unlist(m$find)), jsonlite::read_json(f)) %||% list()
}
mark_columns <- function(x, t) {
  j <- intersect(unlist(table_marks(t)$new_columns), t$data |> names())
  if (!length(j)) return(x)
  x |> flextable::style(j = j, pr_t = officer::fp_text_lite(underlined = TRUE, color = INSERTED_RGB), part = "all")
}

ft <- function(t) {
  flextable::flextable(as.data.frame(t$data)) |>
    mark_columns(t) |>   # 先標色；之後的字型與字級設定套用到所有欄位
    flextable::font(fontname = "Times New Roman", part = "all") |>
    flextable::fontsize(size = if (ncol(t$data) >= 7) 9 else 10, part = "all") |>   # 欄位多的表用 9 pt
    flextable::bold(part = "header") |>
    flextable::padding(padding.top = 1, padding.bottom = 1, part = "all") |>
    flextable::italic(j = intersect("P", names(t$data)), part = "header") |>
    flextable::autofit() |>
    fit_page()
}
# 一般表格（data.frame）也用同樣樣式
ft_df <- function(df) ft(list(data = df))
# 縮放欄寬到頁寬（A4 扣掉 2.5 cm 邊界約 6.3 吋），字體維持 10 pt，必要時換行（fit_to_width 會縮小字體）
fit_page <- function(x, page = 6.3) {
  # 依內容（不依長標題）決定欄寬並留緩衝；標題自動換行，但至少容得下標題中最長的一個字（避免字被拆開）
  hdr <- unlist(x$header$dataset[1, x$col_keys])
  longest_word <- vapply(hdr, function(h) max(nchar(strsplit(h, "[ ,/]+")[[1]]), 0L), 0L)
  w <- pmax(flextable::dim_pretty(x, part = "body")$widths, 0.6, longest_word * 0.085) + 0.12
  w[1] <- min(max(w[1], 1.5), 2.2)
  flextable::width(x, width = w * min(1, page / sum(w)))
}
footnotes <- function(t) {
  marked <- unlist(table_marks(t)$new_footnotes)
  fn <- vapply(t$footnotes, function(x) if (length(marked) && any(startsWith(x, as.character(marked)))) sprintf('[%s]{custom-style="Inserted Text"}', x) else x, "")
  knitr::asis_output(paste0("\n", paste(fn, collapse = "\n\n"), "\n"))
}

# 教學示範標示（每份對外文件第一頁）
demo_labels <- function() knitr::asis_output(paste0(
  "*SYNTHETIC DATA FOR TEACHING \u2014 NOT A REAL STUDY. Patients, investigators and institution are fictional.*\n\n",
  "**This demonstration manuscript was written by AI (Claude Opus 5.5). In a real submission, the text must be written by the authors.**\n\n"))
