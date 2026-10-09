# 產生 JCRP 投稿檔：make manuscript（草稿，可有未完成項目）或 make submission（所有檢查通過才寫入 submission/）。
# 步驟：參考文獻 → 匿名正文 Word → 計字數與頁數 → 首頁 Word → 圖檔轉 JPEG → 寫作指引 → 檢查報告。
args <- commandArgs(trailingOnly = TRUE)
mode <- if (length(args)) args[1] else "draft"
stopifnot(mode %in% c("draft", "submission"))
source("manuscript/R/tables.R")   # tokens.R、common.R
source("manuscript/R/check.R")
source("manuscript/R/render_util.R")

BUILD <- "manuscript/_build"
dir.create(BUILD, showWarnings = FALSE, recursive = TRUE)
journal <- yaml::read_yaml("manuscript/journal.yaml")
meta <- yaml::read_yaml("manuscript/meta.yaml")
cfg <- RcppTOML::parseTOML("config.toml")
cv <- RcppTOML::parseTOML("cv.toml")
FIGURES <- c(`Figure 1` = "results/figures/cohort_flow.png", `Figure 2` = "results/figures/km_efs.png",
             `Figure 3` = "results/figures/km_os.png")
SUPPLEMENTARY <- c(`Figure S1` = "results/figures/love_plot.png", `Figure S2` = "results/figures/ps_overlap.png")

# 1. 參考文獻：JCRP 的 Vancouver 範例不列 DOI／PMID，給 pandoc 的副本移除這兩欄
refs_json <- jsonlite::read_json("manuscript/references.json")
jsonlite::write_json(lapply(refs_json, function(r) r[setdiff(names(r), c("DOI", "PMID"))]),
                     file.path(BUILD, "references_pandoc.json"), auto_unbox = TRUE, pretty = TRUE)

# 2. 匿名正文
render("article.qmd", "JCRP_blinded_article.docx")

# 3. 字數（作者文字填入數字後計算）與頁數
read_text <- function(f) gsub("<!--.*?-->", "", paste(readLines(file.path("manuscript/text", paste0(f, ".md")), encoding = "UTF-8"), collapse = "\n"))
tk <- manuscript_tokens()
texts <- sapply(c("abstract", "introduction", "methods", "results", "discussion", "statements", "figure_legends"),
                function(f) fill_tokens(read_text(f), tk), simplify = FALSE)
wc <- vapply(texts, word_count, 0L)
pg_lines <- pdf_page_lines(file.path(BUILD, "JCRP_blinded_article.docx"))
pages <- if (is.null(pg_lines)) NA_integer_ else length(pg_lines)
counts <- list(abstract_words = wc[["abstract"]], intro_words = wc[["introduction"]],
               text_words = sum(wc[c("introduction", "methods", "results", "discussion")]),
               intro_discussion_words = wc[["introduction"]] + wc[["discussion"]],
               pages = if (length(pages)) pages else NA, figures = length(FIGURES), tables = length(manuscript_tables()))
jsonlite::write_json(counts, file.path(BUILD, "counts.json"), auto_unbox = TRUE, pretty = TRUE)

# 3b. 正文各小標題所在頁碼（STROBE 檢核表用）：依正文順序逐頁比對整行文字
HEADINGS <- c("Abstract", "Introduction", "Materials and Methods", "Study Design and Data Sources", "Patients",
              "Treatment Groups and Outcomes", "Statistical Analysis", "Ethics", "Results", "Results/Patients",
              "Pathologic Complete Response", "Event-Free and Overall Survival", "Sensitivity and Subgroup Analyses",
              "Discussion", "References")
page_map <- list()
if (!is.na(counts$pages)) {
  at <- 1L
  for (h in HEADINGS) {
    hit <- Find(function(i) sub("^Results/", "", h) %in% pg_lines[[i]], seq(at, counts$pages))
    if (!is.null(hit)) { page_map[[h]] <- hit; at <- hit }
  }
}
jsonlite::write_json(page_map, file.path(BUILD, "page_map.json"), auto_unbox = TRUE, pretty = TRUE)

# 4. 首頁、cover letter、補充資料、STROBE 檢核表、分析程式（補充檔）
render("title_page.qmd", "JCRP_title_page.docx")
render("cover_letter.qmd", "JCRP_cover_letter.docx")
render("supplementary.qmd", "JCRP_supplementary_material.docx")
render("strobe_checklist.qmd", "JCRP_STROBE_checklist.docx")
code_zip <- file.path(BUILD, "JCRP_supplementary_code.zip")
unlink(code_zip)
run("zip", c("-r", "-q", "-X", code_zip, "analysis", "Makefile", "-x", "*.DS_Store", "*/.Rhistory"), stdout = FALSE)

# 5. 圖檔（JPEG，另外上傳，不嵌入正文）
px <- journal$limits$image_pixels
jpg <- function(src, label) file.path(BUILD, "figures", paste0(gsub(" ", "_", label), ".jpg"))
fig_out <- system2("uv", c("run", "python", "manuscript/style/figures_to_jpeg.py", px[1], px[2],
                           sprintf("%s=%s", c(FIGURES, SUPPLEMENTARY), jpg(c(FIGURES, SUPPLEMENTARY), names(c(FIGURES, SUPPLEMENTARY))))),
                   stdout = TRUE)
images <- rbindlist(lapply(strsplit(fig_out, " "), function(v) data.table(
  name = basename(v[1]), w = as.integer(v[2]), h = as.integer(v[3]), mb = as.numeric(v[4]) / 1024^2)))

# 6. 寫作指引（給作者，不投稿）
render("writing_guide.qmd", "writing_guide.html", to = "html")

# 7. 檢查
article_xml <- docx_text(file.path(BUILD, "JCRP_blinded_article.docx"))
title_xml <- docx_text(file.path(BUILD, "JCRP_title_page.docx"))
blind_terms <- blind_terms_for(cfg, cv)
files <- list(
  article_mb = file.size(file.path(BUILD, "JCRP_blinded_article.docx")) / 1024^2,
  synthetic_label = c(grepl("SYNTHETIC DATA FOR TEACHING", article_xml), grepl("SYNTHETIC DATA FOR TEACHING", title_xml)),
  ai_demo_label = c(grepl("written by AI", article_xml), grepl("written by AI", title_xml)),
  title_page_has_cjk = grepl("[㐀-鿿]", title_xml), images = images,
  cover_text = docx_text(file.path(BUILD, "JCRP_cover_letter.docx")),
  supp_tables = supplementary_tables(journal$limits$table_max_rows),
  supp_text = docx_text(file.path(BUILD, "JCRP_supplementary_material.docx")),
  strobe = yaml::read_yaml("manuscript/strobe.yaml"), page_map = page_map,
  code_zip_files = system2("unzip", c("-Z1", code_zip), stdout = TRUE),
  package_mb = sum(file.size(c(file.path(BUILD, c("JCRP_title_page.docx", "JCRP_blinded_article.docx",
    "JCRP_cover_letter.docx", "JCRP_supplementary_material.docx", "JCRP_STROBE_checklist.docx")), code_zip,
    list.files(file.path(BUILD, "figures"), full.names = TRUE)))) / 1024^2)
res <- run_checks(texts, meta, manuscript_tables(), counts, journal, fread("manuscript/references_verification.csv"),
                  blind_terms, files)
write_report(res, file.path(BUILD, "check_report.md"), counts)
fwrite(res, file.path(BUILD, "check_results.csv"))   # 給 build_revision.R 讀
n_err <- res[level == "error" & !ok, .N]
cat(sprintf("論文檔已產生於 %s：待修正 %d 項、請確認 %d 項 → %s/check_report.md\n", BUILD, n_err,
            res[level == "warning" & !ok, .N], BUILD))

# 8. 投稿版：全部通過才寫入 submission/
if (mode == "submission") {
  if (n_err > 0) {
    cat("投稿檔未產生：請先處理檢查報告中「待修正」的項目。\n")
    quit(status = 1)
  }
  dir.create("submission/figures", showWarnings = FALSE, recursive = TRUE)
  upload <- c("JCRP_cover_letter.docx", "JCRP_title_page.docx", "JCRP_blinded_article.docx",
              "JCRP_supplementary_material.docx", "JCRP_supplementary_code.zip", "JCRP_STROBE_checklist.docx")
  file.copy(file.path(BUILD, c(upload, "check_report.md")), "submission", overwrite = TRUE)
  file.copy(list.files(file.path(BUILD, "figures"), full.names = TRUE), "submission/figures", overwrite = TRUE)
  write_submission_readme("submission", upload, journal)
  cat("投稿檔已寫入 submission/（上傳清單見 submission/README.md）\n")
}
