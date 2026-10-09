# 各投稿文件（正文、補充資料、cover letter、STROBE 檢核表）共用的排版工具。由 .qmd source。
source("manuscript/R/tables.R")   # tokens.R、common.R
tk <- manuscript_tokens()
cfg <- RcppTOML::parseTOML("config.toml")
cv <- RcppTOML::parseTOML("cv.toml")
meta <- yaml::read_yaml("manuscript/meta.yaml")

# 讀 manuscript/text/<name>.md：去掉作者註解、填入數字代號
section <- function(name) {
  x <- paste(readLines(file.path("manuscript/text", paste0(name, ".md")), encoding = "UTF-8"), collapse = "\n")
  x <- gsub("<!--.*?-->", "", x)           # 作者註解不輸出
  knitr::asis_output(paste0("\n", fill_tokens(x, tk), "\n"))
}
ft <- function(t) {
  flextable::flextable(as.data.frame(t$data)) |>
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
  w <- pmax(flextable::dim_pretty(x, part = "body")$widths, 0.6) + 0.12   # 依內容（不依長標題）決定欄寬並留緩衝；標題自動換行
  w[1] <- min(max(w[1], 1.5), 2.2)
  flextable::width(x, width = w * min(1, page / sum(w)))
}
footnotes <- function(t) knitr::asis_output(paste0("\n", paste(t$footnotes, collapse = "\n\n"), "\n"))

# 教學示範標示（每份對外文件第一頁）
demo_labels <- function() knitr::asis_output(paste0(
  "*SYNTHETIC DATA FOR TEACHING \u2014 NOT A REAL STUDY. Patients, investigators and institution are fictional.*\n\n",
  "**This demonstration manuscript was written by AI (Claude Opus 5.5). In a real submission, the text must be written by the authors.**\n\n"))
