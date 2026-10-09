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
md <- c("# Response to the Editor and Reviewers", "", trimws(resp[["Opening"]]), "")
for (g in unique(vapply(names(comments), group_of, ""))) {
  md <- c(md, paste("##", g), "")
  for (id in names(comments)[vapply(names(comments), group_of, "") == g]) {
    md <- c(md, sprintf("**Comment %s.** *%s*", id, comments[[id]]), "",
            sprintf("**Response:** %s", field(resp[[id]], "Response")), "",
            sprintf("**Changes:** %s", field(resp[[id]], "Changes")), "")
  }
}
md <- c(md, trimws(resp[["Closing"]]))
response_md <- file.path(REV, "response.md")
writeLines(fill_tokens(paste(md, collapse = "\n"), tk), response_md)

# 2. 標示修改處：上次投稿版（git tag）vs 目前版本，都先填好數字再比對
sections <- c("abstract", "introduction", "methods", "results", "discussion", "statements", "figure_legends")
for (d in c("old", "new")) dir.create(file.path(REV, d))
for (f in sections) {
  old <- system2("git", c("show", sprintf("%s:manuscript/text/%s.md", rev$baseline_tag, f)), stdout = TRUE)
  writeLines(fill_tokens(strip(old), tk), file.path(REV, "old", paste0(f, ".md")))
  writeLines(fill_tokens(strip(readLines(file.path("manuscript/text", paste0(f, ".md")), encoding = "UTF-8")), tk),
             file.path(REV, "new", paste0(f, ".md")))
}
run("uv", c("run", "python", "manuscript/style/mark_changes.py", file.path(REV, "old"), file.path(REV, "new"),
            file.path(REV, "marked")), stdout = FALSE)

# 3. 產生檔案
env_resp <- paste0("MS_RESPONSE=", normalizePath(response_md))
render("response.qmd", "JCRP_response_to_reviewers.docx", env = env_resp, dest = REV)
render("article.qmd", "JCRP_revised_article_marked.docx", dest = REV,
       env = c(env_resp, paste0("MS_TEXT_DIR=", normalizePath(file.path(REV, "marked")))))
invisible(file.copy(file.path(BUILD, "JCRP_blinded_article.docx"), file.path(REV, "JCRP_revised_article_clean.docx")))
invisible(file.copy(file.path(BUILD, c("JCRP_supplementary_material.docx", "JCRP_supplementary_code.zip", "JCRP_STROBE_checklist.docx")), REV))
dir.create(file.path(REV, "figures")); invisible(file.copy(list.files(file.path(BUILD, "figures"), full.names = TRUE), file.path(REV, "figures")))

# 4. 檢查
chk <- list()
add <- function(item, ok, detail = "") chk[[length(chk) + 1]] <<- data.table(item = item, ok = ok, detail = detail)
base <- fread(file.path(BUILD, "check_results.csv"))
add("修訂稿通過全部投稿格式檢查（make manuscript）", base[level == "error" & !ok, .N] == 0,
    paste(base[level == "error" & !ok, item], collapse = "、"))
add(sprintf("每一則審稿意見都有回覆（%d 則）", length(comments)), TRUE, paste(names(comments), collapse = "、"))
marked_xml <- paste(system2("unzip", c("-p", file.path(REV, "JCRP_revised_article_marked.docx"), "word/document.xml"), stdout = TRUE), collapse = "")
add("標示版：新增文字有底線、刪除文字有刪除線", grepl("<w:u w:val=\"single\"", marked_xml) && grepl("<w:strike", marked_xml))
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
  sprintf("期刊要求在 %d 天內交回。修訂稿不必再交首頁檔（Title Page）。", rev$due_days), "",
  "| 檔案 | 用途 |", "|---|---|",
  "| `JCRP_response_to_reviewers.docx` | 逐條回覆（匿名） |",
  "| `JCRP_revised_article_marked.docx` | 標示修改處的修訂稿：最前面是逐條回覆；新增加底線、刪除加刪除線 |",
  "| `JCRP_revised_article_clean.docx` | 乾淨修訂稿 |",
  "| `JCRP_supplementary_material.docx` | 補充資料（新增 Table S4、Figure S2） |",
  "| `JCRP_supplementary_code.zip` | 分析程式（含事後分析） |",
  "| `JCRP_STROBE_checklist.docx` | STROBE 檢核表（頁碼已更新） |",
  "| `figures/` | 正文圖 1–3、補充圖 S1–S2（JPEG） |", "",
  "檢查結果見 `check_report.md`。"), file.path(out, "README.md"))
cat(sprintf("修訂稿已寫入 %s（%d 則意見全部回覆）\n", out, length(comments)))
