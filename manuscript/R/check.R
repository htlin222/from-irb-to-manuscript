# 投稿檔檢查：依 manuscript/journal.yaml 的規定逐項檢查，輸出 manuscript/_build/check_report.md。
# 等級：error（投稿前必須修正，make submission 會擋下）、warning（請人工確認）。
suppressPackageStartupMessages(library(data.table))

word_count <- function(x) {
  x <- gsub("<!--.*?-->", "", x)
  x <- gsub("\\[@[^]]*\\]", "", x)                         # 引用
  x <- gsub("(?m)^#+ .*$", "", x, perl = TRUE)             # 小標題不計
  x <- gsub("[*_`#>]", " ", x)
  length(Filter(nzchar, strsplit(trimws(x), "\\s+")[[1]]))
}
section_body <- function(x, heading) {                     # 摘要中某段（**Background:** ...）
  m <- regmatches(x, regexec(paste0("(?s)\\*\\*", heading, ":\\*\\*(.*?)(?=\\n\\*\\*[A-Z][^*]+:\\*\\*|$)"), x, perl = TRUE))[[1]]
  if (length(m) > 1) m[2] else NA_character_
}

run_checks <- function(texts, meta, tables, counts, journal, refs_status, blind_terms, files) {
  out <- list()
  add <- function(level, item, ok, detail = "") {
    out[[length(out) + 1]] <<- data.table(level = level, item = item, ok = ok, detail = detail)
  }
  lim <- journal$limits
  all_text <- paste(unlist(texts), collapse = "\n")

  # 1. 作者還沒寫的部分
  ph <- vapply(texts, function(x) lengths(regmatches(x, gregexpr("\\[TO BE WRITTEN", x))), 0L)
  add("error", "正文佔位文字已全部改寫", sum(ph) == 0,
      if (sum(ph)) paste(sprintf("%s：%d 處", names(ph)[ph > 0], ph[ph > 0]), collapse = "；") else "")
  todo <- grep("TODO", unlist(meta), value = TRUE)
  add("error", "meta.yaml（首頁資訊）已填完", length(todo) == 0, if (length(todo)) sprintf("尚有 %d 個 TODO", length(todo)) else "")

  # 2. 字數
  add("error", sprintf("摘要 ≤ %d 字", lim$abstract_words), counts$abstract_words <= lim$abstract_words,
      sprintf("目前 %d 字", counts$abstract_words))
  heads <- journal$abstract$headings
  add("error", "摘要四段標題齊全且依序", all(!is.na(vapply(heads, function(h) section_body(texts$abstract, h), ""))),
      paste(heads, collapse = " / "))
  iw <- lim$introduction_words
  add("error", sprintf("前言 %d–%d 字", iw[1], iw[2]), counts$intro_words >= iw[1] && counts$intro_words <= iw[2],
      sprintf("目前 %d 字", counts$intro_words))
  add("error", sprintf("正文 ≤ %d 字（不含摘要、參考文獻、表格）", lim$main_text_words),
      counts$text_words <= lim$main_text_words, sprintf("目前 %d 字", counts$text_words))
  legends <- regmatches(texts$figure_legends, gregexpr("\\*\\*Figure [0-9]+\\.\\*\\*[^\n]*", texts$figure_legends))[[1]]
  lw <- vapply(legends, function(l) word_count(sub("^\\*\\*Figure [0-9]+\\.\\*\\*", "", l)), 0L)
  add("error", sprintf("每則圖說 ≤ %d 字", lim$figure_legend_words), all(lw <= lim$figure_legend_words),
      paste(sprintf("Figure %d：%d 字", seq_along(lw), lw), collapse = "；"))
  kw <- unlist(meta$keywords)
  add("error", sprintf("關鍵字 ≥ %d 個", lim$keywords_min), sum(kw != "TODO") >= lim$keywords_min,
      sprintf("目前 %d 個", sum(kw != "TODO")))
  add("error", sprintf("作者 ≤ %d 位", lim$authors_max), length(meta$authors) <= lim$authors_max,
      sprintf("目前 %d 位", length(meta$authors)))

  # 3. 表格
  for (t in tables) {
    add("error", sprintf("%s：≤ %d 列、≤ %d 欄", sub("\\..*$", "", t$title), lim$table_max_rows, lim$table_max_columns),
        nrow(t$data) <= lim$table_max_rows && ncol(t$data) <= lim$table_max_columns,
        sprintf("%d 列 × %d 欄", nrow(t$data), ncol(t$data)))
  }

  # 4. 參考文獻
  keys <- unique(unlist(regmatches(all_text, gregexpr("(?<=@)[A-Za-z0-9_]+", all_text, perl = TRUE))))
  unknown <- setdiff(keys, refs_status$citation_key)
  unverified <- refs_status[citation_key %in% keys & !grepl("^verified", status), citation_key]
  add("error", "引用的文獻都在 references.yaml 且已查證", !length(unknown) && !length(unverified),
      paste(c(if (length(unknown)) paste("未列入：", paste(unknown, collapse = "、")),
              if (length(unverified)) paste("未通過查證：", paste(unverified, collapse = "、"))), collapse = "；"))
  add("warning", sprintf("參考文獻約 %d 篇以內", lim$references_about), length(keys) <= lim$references_about,
      sprintf("目前引用 %d 篇", length(keys)))
  before_punct <- regmatches(all_text, gregexpr("[A-Za-z0-9)]\\s?\\[@[^]]*\\][.,;:]", all_text))[[1]]
  add("warning", "引用放在標點之後（如 ...trials.[@key]）", !length(before_punct),
      if (length(before_punct)) paste(head(before_punct, 3), collapse = "  ") else "")

  # 5. 雙盲
  hits <- blind_terms[vapply(blind_terms, function(w) grepl(w, all_text, fixed = TRUE), TRUE)]
  add("error", "匿名正文不含作者姓名、單位、IRB 編號", !length(hits), paste(hits, collapse = "、"))
  self_ref <- regmatches(all_text, gregexpr("(?i)\\bour (previous|prior|earlier) (study|report|work)", all_text, perl = TRUE))[[1]]
  add("warning", "沒有自我揭露身分的寫法（如 our previous study）", !length(self_ref), paste(self_ref, collapse = "、"))

  # 6. 用詞與統計寫法（JCRP）
  sig <- regmatches(all_text, gregexpr("(?i)\\bsignifican[a-z]*", all_text, perl = TRUE))[[1]]
  add("warning", "避免非統計意義的 significant", !length(sig), if (length(sig)) sprintf("出現 %d 次，請確認皆指統計顯著", length(sig)) else "")
  plt <- regmatches(all_text, gregexpr("(?i)\\bp\\s*[<>]\\s*0?\\.0[0-9]+", all_text, perl = TRUE))[[1]]
  add("warning", "P 值寫精確值（不寫 P < 0.05）", !length(plt), paste(plt, collapse = "、"))
  lowp <- regmatches(all_text, gregexpr("(?<![*A-Za-z])p\\s*=\\s*0?\\.[0-9]", all_text, perl = TRUE))[[1]]
  add("warning", "P 值用大寫斜體 *P*（代號 {{..._p}} 已處理）", !length(lowp), paste(lowp, collapse = "、"))
  digits <- regmatches(all_text, gregexpr("(?<![0-9.,%/\\-–])\\b[1-9]\\b(?![0-9.,%/\\-–])(?! ?(years?|months?|days?|cycles?|mg|%))",
                                          gsub("\\{\\{[a-z0-9_]+\\}\\}|\\*\\*Figure [0-9]+\\.\\*\\*|Table [0-9]|Figure [0-9]|S[0-9]|T[0-4]|N[0-3]|receptor 2|[0-9]\\+", "", all_text),   # HER2 正式名稱、IHC 分數不算
                                          perl = TRUE))[[1]]
  add("warning", "1 到 10 的數字用英文拼寫（one … ten）", !length(digits),
      if (length(digits)) sprintf("疑似 %d 處，請檢查", length(digits)) else "")

  # 7. 必要聲明與標示
  add("error", "資料可取得性聲明已撰寫", !grepl("Data Availability Statement\\s*\\n+\\s*\\[TO BE WRITTEN", texts$statements))
  add("error", "生成式 AI 使用揭露已撰寫", !grepl("Use of Generative AI\\s*\\n+\\s*\\[TO BE WRITTEN", texts$statements))
  add("error", "兩個檔案都有「synthetic data for teaching」標示", all(files$synthetic_label))
  add("warning", "本稿為 AI 撰寫之教學示範稿（不得投稿；真實投稿時內文須由作者親自撰寫）", !any(files$ai_demo_label),
      if (any(files$ai_demo_label)) "兩個檔案都標示了 AI 撰寫，符合教學示範；真實投稿前須由作者重寫並移除標示" else "")
  add("error", "首頁檔沒有中文字（英文投稿）", !files$title_page_has_cjk, if (files$title_page_has_cjk) "請檢查 cv.toml 的電話、meta.yaml" else "")

  # 8. 檔案
  add("error", sprintf("匿名正文檔 ≤ %d MB", lim$blinded_file_mb), files$article_mb <= lim$blinded_file_mb,
      sprintf("%.2f MB", files$article_mb))
  for (i in seq_len(nrow(files$images))) {
    im <- files$images[i]
    add("error", sprintf("%s：JPEG、≤ 1 MB、≤ %d×%d 像素", im$name, lim$image_pixels[1], lim$image_pixels[2]),
        im$mb <= 1 && im$w <= lim$image_pixels[1] && im$h <= lim$image_pixels[2], sprintf("%.2f MB，%d×%d", im$mb, im$w, im$h))
  }
  rbindlist(out)
}

write_report <- function(res, path, counts) {
  mark <- function(r) if (r$ok) "■" else if (r$level == "error") "□ **待修正**" else "⚠ 請確認"
  lines <- c("# 投稿檔檢查報告（JCRP）", "",
             "> 依 `manuscript/journal.yaml`。■ 通過　□ 必須修正（make submission 會擋下）　⚠ 請人工確認", "",
             sprintf("- 待修正 %d 項、請確認 %d 項、通過 %d 項", res[level == "error" & !ok, .N], res[level == "warning" & !ok, .N], res[ok == TRUE, .N]),
             sprintf("- 字數：摘要 %d；前言 %d；正文 %d；前言＋討論 %d；匿名正文檔 %s 頁",
                     counts$abstract_words, counts$intro_words, counts$text_words, counts$intro_discussion_words, counts$pages), "",
             "| | 項目 | 說明 |", "|---|---|---|")
  for (i in seq_len(nrow(res))) lines <- c(lines, sprintf("| %s | %s | %s |", mark(res[i]), res$item[i], res$detail[i]))
  writeLines(lines, path)
}
