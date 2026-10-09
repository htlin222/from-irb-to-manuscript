# 期刊修訂版：make revision。依 manuscript/revision.yaml：
#   回覆信（逐條，匿名）＋標示修改處的修訂稿（回覆放在最前面，新增加底線、刪除加刪除線）＋乾淨修訂稿＋補充資料。
# 前提：已執行 make manuscript（build.R），且其檢查沒有「待修正」項目。輸出 submission/revision<N>/。
source("manuscript/R/tables.R")
BUILD <- "manuscript/_build"
cfg <- RcppTOML::parseTOML("config.toml"); cv <- RcppTOML::parseTOML("cv.toml")
source("manuscript/R/render_util.R")
rev <- yaml::read_yaml("manuscript/revision.yaml")
REV <- file.path(BUILD, sprintf("revision%d", rev$round))
unlink(REV, recursive = TRUE); dir.create(REV, recursive = TRUE)
tk <- manuscript_tokens()
strip <- function(x) gsub("<!--.*?-->", "", paste(x, collapse = "\n"))

# 1. 審稿意見（編號 E1、R1.1…）與回覆，逐條配對
dec <- readLines(rev$decision, encoding = "UTF-8")
m <- regmatches(dec, regexec("^((?:E|R)[0-9]+(?:\\.[0-9]+)?)\\.\\s+(.*)$", dec, perl = TRUE))
comments <- setNames(vapply(Filter(length, m), `[`, "", 3), vapply(Filter(length, m), `[`, "", 2))
src <- strip(readLines(rev$response, encoding = "UTF-8"))
parts <- strsplit(src, "\n## ")[[1]][-1]
resp <- setNames(sub("^[^\n]*\n", "", parts), sub("\n.*$", "", parts))
missing <- setdiff(names(comments), names(resp)); extra <- setdiff(names(resp), c(names(comments), "Opening", "Closing"))
if (length(missing) || length(extra)) stop("回覆與審稿意見不一致：未回覆 ", paste(missing, collapse = "、"), "；多出 ", paste(extra, collapse = "、"))
field <- function(txt, label) trimws(sub(paste0("(?s)^.*?", label, ":\\s*(.*?)(\\n\\s*\\n(Response|Changes):.*)?$"), "\\1", txt, perl = TRUE))
group_of <- function(id) if (startsWith(id, "E")) "Editorial Office" else sprintf("Reviewer %s", sub("^R([0-9]+).*$", "\\1", id))
compose_response <- function(summary_md) {
md <- c("# Response to the Editor and Reviewers", "", trimws(resp[["Opening"]]), "", summary_md, "")
for (g in unique(vapply(names(comments), group_of, ""))) {
  md <- c(md, paste("##", g), "")
  for (id in names(comments)[vapply(names(comments), group_of, "") == g]) {
    md <- c(md, sprintf("**Comment %s.** *%s*", id, comments[[id]]), "",
            sprintf("**Response:** %s", field(resp[[id]], "Response")), "",
            sprintf("**Changes:** %s", field(resp[[id]], "Changes")), "")
  }
}
md <- c(md, trimws(resp[["Closing"]]))
writeLines(fill_tokens(paste(md, collapse = "\n"), tk), response_md)
}
response_md <- file.path(REV, "response.md")

# 2. 標示修改處：上次投稿版（git tag）vs 目前版本，都先填好數字再比對
sections <- c("abstract", "introduction", "methods", "results", "discussion", "statements", "figure_legends")
for (d in c("old", "new")) dir.create(file.path(REV, d))
for (f in sections) {
  old <- system2("git", c("show", sprintf("refs/tags/%s:manuscript/text/%s.md", rev$baseline_tag, f)), stdout = TRUE)
  writeLines(fill_tokens(strip(old), tk), file.path(REV, "old", paste0(f, ".md")))
  writeLines(fill_tokens(strip(readLines(file.path("manuscript/text", paste0(f, ".md")), encoding = "UTF-8")), tk),
             file.path(REV, "new", paste0(f, ".md")))
}
run("uv", c("run", "python", "manuscript/style/mark_changes.py", file.path(REV, "old"), file.path(REV, "new"),
            file.path(REV, "marked")), stdout = FALSE)

# 3. 產生檔案。回覆信開頭的「修改總覽」列出每處修改在標示版的頁碼：先產生一次找頁碼，寫進回覆信再產生，
#    直到頁碼不再變動（總覽表本身會讓後面的頁碼往後移）
SECTION_LABELS <- c(abstract = "Abstract", introduction = "Introduction", methods = "Materials and Methods",
                    results = "Results", discussion = "Discussion", statements = "Statements",
                    figure_legends = "Figure Legends")
changes <- rbindlist(jsonlite::read_json(file.path(REV, "marked", "changes.json")))
changes <- changes[order(match(section, names(SECTION_LABELS)))]   # 依論文順序（檔案是依字母排）
changes[, `:=`(label = SECTION_LABELS[section],
               part = fifelse(nzchar(subsection) & subsection != SECTION_LABELS[section], subsection, "\u2014"))]
# 正文以外的修改（表格、補充資料；revision.yaml other_changes）：有 find 者在標示版找頁碼，表格的新欄位與註腳也標色
other <- rbindlist(lapply(rev$other_changes, function(o) data.table(label = o$section, part = o$part,
                                                                    snippet = o$find %||% NA_character_)))
changes <- rbind(changes[, .(label, part, snippet)], other)
marks_json <- file.path(REV, "table_marks.json")
jsonlite::write_json(Filter(function(o) length(o$new_columns) || length(o$new_footnotes), rev$other_changes),
                     marks_json, auto_unbox = FALSE)
norm_txt <- function(x) gsub("\\s+", " ", gsub("-\\s*$", "-", x))
find_pages <- function(pages) {
  joined <- vapply(pages, function(l) norm_txt(paste(l, collapse = " ")), "")
  start <- which(vapply(pages, function(l) "Abstract" %in% l, TRUE))
  start <- if (length(start)) max(start[start > 1], start[1]) else 1L   # 跳過最前面的逐條回覆
  # 每處修改都從論文第一頁（逐條回覆之後）找起；段落開頭的文字足以定位
  vapply(changes$snippet, function(sn) {
    if (is.na(sn)) return(NA_integer_)
    hit <- Find(function(i) grepl(norm_txt(sn), joined[i], fixed = TRUE), seq(start, length(joined)))
    if (is.null(hit)) NA_integer_ else hit
  }, 0L, USE.NAMES = FALSE)
}
# 依論文順序列出引用的文獻（= 參考文獻編號順序）
cited_keys <- function(dir) {
  files <- file.path(dir, paste0(names(SECTION_LABELS), ".md"))
  txt <- paste(unlist(lapply(files[file.exists(files)], readLines, encoding = "UTF-8")), collapse = " ")
  unique(regmatches(txt, gregexpr("(?<=@)[A-Za-z0-9_]+", txt, perl = TRUE))[[1]])
}
ref_label <- function(key, order) {   # 例：Schneeweiss et al., 2013 (reference 16)
  r <- Filter(function(x) identical(x$id, key), jsonlite::read_json("manuscript/references.json"))[[1]]
  sprintf("%s%s, %s (reference %d)", r$author[[1]]$family, if (length(r$author) > 1) " et al." else "",
          r$issued$`date-parts`[[1]][[1]], match(key, order))
}
summary_table <- function(pg) {
  x <- copy(changes)[, page := pg]
  by_part <- x[, .(pages = if (all(is.na(snippet))) "\u2014" else if (anyNA(page)) "?"
                   else if (min(page) == max(page)) as.character(min(page))
                   else sprintf("%d\u2013%d", min(page), max(page))), by = .(label, part)]
  new_keys <- setdiff(cited_keys(file.path(REV, "new")), cited_keys(file.path(REV, "old")))   # 本輪新增的參考文獻
  c("## Summary of Changes", "",
    "Page numbers refer to the marked revised manuscript. New text is shown in blue and underlined; deleted text in red and struck through.", "",
    "| Section | Part | Page(s) |", "|---|---|---|",
    by_part[label %in% SECTION_LABELS, sprintf("| %s | %s | %s |", label, part, pages)],
    if (length(new_keys)) sprintf("| References | Added: %s | \u2014 |",
                                  paste(vapply(new_keys, ref_label, "", order = cited_keys(file.path(REV, "new"))), collapse = "; ")),
    by_part[!label %in% SECTION_LABELS, sprintf("| %s | %s | %s |", label, part, pages)])
}
env_resp <- paste0("MS_RESPONSE=", normalizePath(response_md, mustWork = FALSE))
env_text <- c(paste0("MS_TEXT_DIR=", normalizePath(file.path(REV, "marked"))), paste0("MS_TABLE_MARKS=", normalizePath(marks_json)))
pg <- rep(NA_integer_, nrow(changes))
for (pass in 1:4) {
  compose_response(summary_table(pg))
  render("article.qmd", "JCRP_revised_article_marked.docx", dest = REV, env = c(env_resp, env_text))
  new_pg <- find_pages(pdf_page_lines(file.path(REV, "JCRP_revised_article_marked.docx")))
  if (identical(new_pg, pg)) break
  pg <- new_pg
}
render("response.qmd", "JCRP_response_to_reviewers.docx", env = env_resp, dest = REV)
invisible(file.copy(file.path(BUILD, "JCRP_blinded_article.docx"), file.path(REV, "JCRP_revised_article_clean.docx")))
invisible(file.copy(file.path(BUILD, c("JCRP_supplementary_material.docx", "JCRP_supplementary_code.zip")), REV))
# STROBE 檢核表（Supplementary File S2）：頁碼與乾淨修訂稿相同（乾淨修訂稿即 make manuscript 的匿名正文）
render("strobe_checklist.qmd", "JCRP_STROBE_checklist.docx", dest = REV,
       env = "MS_STROBE_REF=the clean revised manuscript (JCRP_revised_article_clean.docx)")
dir.create(file.path(REV, "figures")); invisible(file.copy(list.files(file.path(BUILD, "figures"), full.names = TRUE), file.path(REV, "figures")))

# 4. 檢查
chk <- list()
add <- function(item, ok, detail = "") chk[[length(chk) + 1]] <<- data.table(item = item, ok = ok, detail = detail)
base <- fread(file.path(BUILD, "check_results.csv"))
add("修訂稿通過全部投稿格式檢查（make manuscript）", base[level == "error" & !ok, .N] == 0,
    paste(base[level == "error" & !ok, item], collapse = "、"))
add(sprintf("每一則審稿意見都有回覆（%d 則）", length(comments)), TRUE, paste(names(comments), collapse = "、"))
marked_xml <- paste(system2("unzip", c("-p", file.path(REV, "JCRP_revised_article_marked.docx"), "word/document.xml"), stdout = TRUE), collapse = "")
add("標示版：新增文字用「Inserted Text」（藍色底線）、刪除文字用「Deleted Text」（紅色刪除線）",
    grepl("w:rStyle w:val=\"InsertedText\"", marked_xml) && grepl("w:rStyle w:val=\"DeletedText\"", marked_xml))
lost <- !is.na(changes$snippet) & is.na(pg)
add(sprintf("修改總覽：%d 處修改都找到所在頁碼，且頁碼已穩定", sum(!is.na(changes$snippet))), !any(lost) && identical(new_pg, pg),
    paste(changes$snippet[lost], collapse = "；"))
if (any(lengths(lapply(rev$other_changes, `[[`, "new_columns"))))
  add("標示版：表格新增的欄位以藍色底線標示", grepl("w:color w:val=\"1F5FBF\"", marked_xml))
add("標示版：逐條回覆放在檔案最前面", regexpr("Response to the Editor and Reviewers", marked_xml) < regexpr(">Abstract<", marked_xml))
bt <- blind_terms_for(cfg, cv)
for (f in c("JCRP_response_to_reviewers.docx", "JCRP_revised_article_marked.docx")) {
  txt <- docx_text(file.path(REV, f))
  hits <- bt[vapply(bt, function(w) grepl(w, txt, fixed = TRUE), TRUE)]
  add(sprintf("%s：匿名（不含作者、單位、IRB 編號）", f), !length(hits), paste(hits, collapse = "、"))
  add(sprintf("%s：有教學示範標示", f), grepl("written by AI", txt) && grepl("SYNTHETIC DATA", txt))
}
res <- rbindlist(chk)
writeLines(c(sprintf("# 修訂版檢查（第 %d 輪）", rev$round), "", "| | 項目 | 說明 |", "|---|---|---|",
             res[, sprintf("| %s | %s | %s |", fifelse(ok, "■", "□ **待修正**"), item, detail)]), file.path(REV, "check_report.md"))
if (res[ok == FALSE, .N] > 0) { print(res[ok == FALSE]); stop("修訂版檢查未通過，見 ", file.path(REV, "check_report.md")) }

# 5. 寫入 submission/revision<N>/
out <- file.path("submission", basename(REV))
unlink(out, recursive = TRUE); dir.create(out, recursive = TRUE)
invisible(file.copy(list.files(REV, full.names = TRUE, pattern = "\\.(docx|zip|md)$"), out))
invisible(file.copy(file.path(REV, "figures"), out, recursive = TRUE))
unlink(file.path(out, "response.md"))
writeLines(c(
  sprintf("# JCRP 修訂稿（第 %d 輪，由 make revision 產生，請勿手改）", rev$round), "",
  "> ⚠️ **教學示範：資料為模擬（synthetic data for teaching）；論文與回覆由 AI（Claude Opus 5.5）撰寫，不得投稿。**",
  "> 真實投稿時，修訂內容與回覆信必須由作者親自撰寫。", "",
  if (is.null(rev$due_days)) "決定信未載明交回期限。修訂稿不必再交首頁檔（Title Page）。"
  else sprintf("期刊要求在 %d 天內交回。修訂稿不必再交首頁檔（Title Page）。", rev$due_days), "",
  "| 檔案 | 用途 |", "|---|---|",
  "| `JCRP_response_to_reviewers.docx` | 逐條回覆（匿名） |",
  "| `JCRP_revised_article_marked.docx` | 標示修改處的修訂稿：最前面是逐條回覆與修改總覽（附頁碼）；新增為藍色底線、刪除為紅色刪除線 |",
  "| `JCRP_revised_article_clean.docx` | 乾淨修訂稿 |",
  "| `JCRP_supplementary_material.docx` | 補充資料 |",
  "| `JCRP_supplementary_code.zip` | 分析程式（含事後分析） |",
  "| `JCRP_STROBE_checklist.docx` | STROBE 檢核表（Supplementary File S2；頁碼對應乾淨修訂稿） |",
  "| `figures/` | 正文圖與補充圖（JPEG） |", "",
  "本輪正文以外的修改：", "", sprintf("- %s：%s", vapply(rev$other_changes, `[[`, "", "section"),
                                       vapply(rev$other_changes, `[[`, "", "part")), "",
  "檢查結果見 `check_report.md`。"), file.path(out, "README.md"))
cat(sprintf("修訂稿已寫入 %s（%d 則意見全部回覆）\n", out, length(comments)))
