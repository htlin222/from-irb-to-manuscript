# 參考文獻查證：manuscript/references.yaml 的每個 DOI 都向 Crossref 與 PubMed 查詢，
# 互相比對並與預期的第一作者／年份比對；通過者寫入 references.json（CSL-JSON；書目全部來自官方資料庫）。
# 產出：manuscript/references.json（CSL-JSON，給 pandoc 排版）、manuscript/references_verification.csv。有任何一篇失敗則以非零狀態結束。
# 執行：make references
suppressPackageStartupMessages({
  library(yaml); library(jsonlite); library(data.table)
})

refs <- read_yaml("manuscript/references.yaml")
ua <- "her2-neoadjuvant-study reference check (R jsonlite)"
get_json <- function(url) {
  h <- curl::new_handle(useragent = ua)
  tryCatch(fromJSON(rawToChar(curl::curl_fetch_memory(url, handle = h)$content), simplifyVector = FALSE),
           error = function(e) NULL)
}
norm <- function(x) tolower(gsub("[^a-z0-9]", "", tolower(iconv(x, "UTF-8", "ASCII//TRANSLIT"))))
strip_tags <- function(x) trimws(gsub("\\s+", " ", gsub("<[^>]+>", "", x)))
similar <- function(a, b) {
  a <- norm(a); b <- norm(b)
  if (!nzchar(a) || !nzchar(b)) return(NA_real_)
  1 - adist(a, b)[1, 1] / max(nchar(a), nchar(b))
}
first_page <- function(p) sub("[-–].*$", "", p %||% "")
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || identical(a, "")) b else a

# 注意：一律用 [[ ]] 取欄位；R 的 $ 會部分比對（例如 m$issue 會誤抓 m$issued）
crossref <- function(doi) {
  j <- get_json(paste0("https://api.crossref.org/works/", utils::URLencode(doi, reserved = TRUE)))
  if (is.null(j) || is.null(j[["message"]])) return(NULL)
  m <- j[["message"]]
  issued <- m[["published-print"]] %||% m[["issued"]]
  sub_t <- unlist(m[["subtitle"]])[1] %||% ""   # Crossref 把副標題另外登記
  list(title = strip_tags(paste0(unlist(m[["title"]])[1] %||% "", if (nzchar(sub_t)) paste0(": ", sub_t) else "")), journal = unlist(m[["container-title"]])[1] %||% "",
       journal_short = unlist(m[["short-container-title"]])[1] %||% "",
       authors = lapply(m[["author"]] %||% list(), function(a) list(family = a[["family"]] %||% a[["name"]] %||% "", given = a[["given"]] %||% "")),
       year = as.integer(issued[["date-parts"]][[1]][[1]]), volume = m[["volume"]] %||% "", issue = m[["issue"]] %||% "",
       pages = m[["page"]] %||% (m[["article-number"]] %||% ""), doi = tolower(m[["DOI"]]))
}

pubmed <- function(doi) {
  s <- get_json(paste0("https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&retmode=json&term=",
                       utils::URLencode(paste0(doi, "[doi]"), reserved = TRUE)))
  Sys.sleep(0.4)   # NCBI：無 API key 時每秒最多 3 次
  ids <- unlist(s[["esearchresult"]]$idlist)
  if (length(ids) != 1) return(NULL)
  r <- get_json(paste0("https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&retmode=json&id=", ids))
  Sys.sleep(0.4)
  x <- r[["result"]][[ids]]
  if (is.null(x)) return(NULL)
  aid <- vapply(x[["articleids"]], function(a) if (a[["idtype"]] == "doi") a[["value"]] else "", "")
  people <- Filter(function(a) identical(a[["authtype"]], "Author"), x[["authors"]])   # 排除團體作者
  authors <- lapply(people, function(a) parse_pubmed_name(a[["name"]]))
  list(pmid = ids, title = sub("\\.$", "", strip_tags(x[["title"]])), journal = x[["source"]], year = as.integer(substr(x[["pubdate"]], 1, 4)),
       volume = x[["volume"]], issue = x[["issue"]], pages = x[["pages"]], doi = tolower(aid[nzchar(aid)][1] %||% ""),
       authors = authors)
}

# PubMed 的姓名格式是「姓 名字縮寫 [字尾]」，例如 "Geyer CE Jr"、"de la Haba-Rodriguez J"
parse_pubmed_name <- function(name) {
  tok <- strsplit(trimws(name), " +")[[1]]
  suffix <- if (length(tok) > 2 && tok[length(tok)] %in% c("Jr", "Sr", "2nd", "3rd", "II", "III", "IV")) tok[length(tok)] else ""
  if (nzchar(suffix)) tok <- tok[-length(tok)]
  if (length(tok) > 1 && grepl("^[A-Z]+$", tok[length(tok)])) {
    list(family = paste(tok[-length(tok)], collapse = " "), given = tok[length(tok)], suffix = suffix)
  } else list(family = paste(tok, collapse = " "), given = "", suffix = suffix)
}
# Crossref 給全名（"Kari Lock"、"Alan M."）→ NLM 縮寫（"KL"、"AM"）
initials <- function(given) paste(substr(Filter(nzchar, strsplit(gsub("\\.", " ", given), "[ -]+")[[1]]), 1, 1), collapse = "")
results <- list(); bib <- list()
for (r in refs) {
  cr <- crossref(r$doi); pm <- pubmed(r$doi)
  chk <- list(
    crossref_found = !is.null(cr),
    pubmed_found = !is.null(pm),
    doi_matches = !is.null(pm) && identical(pm$doi, tolower(r$doi)),
    title_similarity = if (!is.null(cr) && !is.null(pm)) round(similar(cr$title, pm$title), 3) else NA_real_,
    first_author_ok = !is.null(cr) && length(cr$authors) > 0 && grepl(norm(r$expect$first_author), norm(cr$authors[[1]]$family), fixed = TRUE),
    year_ok = if (!is.null(pm)) pm$year == r$expect$year else (!is.null(cr) && abs(cr$year - r$expect$year) <= 1),
    # 只比對兩邊都有的欄位（線上搶先版的 Crossref 紀錄常缺卷期頁碼）
    volume_page_agree = if (!is.null(cr) && !is.null(pm))
      (!nzchar(cr$volume) || identical(cr$volume, pm$volume)) &&
      (!nzchar(first_page(cr$pages)) || first_page(cr$pages) == first_page(pm$pages)) else NA
  )
  core <- chk$crossref_found && chk$first_author_ok && chk$year_ok
  status <- if (!core) "FAIL" else if (chk$pubmed_found && chk$doi_matches && isTRUE(chk$title_similarity >= 0.9) &&
                                         isTRUE(chk$volume_page_agree)) "verified (Crossref + PubMed)"
            else if (!chk$pubmed_found) "verified (Crossref; not indexed in PubMed)" else "CHECK"
  results[[length(results) + 1]] <- data.table(
    citation_key = r$key, topic = r$topic, doi = r$doi, pmid = pm$pmid %||% "", status = status,
    first_author = if (!is.null(cr) && length(cr$authors)) cr$authors[[1]]$family else "",
    year = pm$year %||% (cr$year %||% NA_integer_), journal = pm$journal %||% (cr$journal_short %||% cr$journal %||% ""),
    title = pm$title %||% (cr$title %||% ""), title_similarity = chk$title_similarity,
    volume_page_agree = chk$volume_page_agree, checked_on = as.character(Sys.Date()))
  if (status != "FAIL") {
    # PubMed 為正式刊出版本且姓名已是 NLM 格式，優先；PubMed 未收錄時用 Crossref 並轉成縮寫
    people <- if (!is.null(pm) && length(pm$authors)) pm$authors else
      lapply(cr$authors, function(a) list(family = a$family, given = initials(a$given), suffix = ""))
    csl <- list(
      id = r$key, type = "article-journal",
      author = lapply(people, function(a) c(list(family = a$family, given = a$given),
                                            if (nzchar(a$suffix %||% "")) list(suffix = a$suffix), list(`parse-names` = FALSE))),
      title = pm$title %||% cr$title, `container-title` = pm$journal %||% (cr$journal_short %||% cr$journal),
      issued = list(`date-parts` = list(list(as.integer(pm$year %||% cr$year)))),
      volume = pm$volume %||% cr$volume, page = pm$pages %||% cr$pages, DOI = tolower(r$doi), PMID = pm$pmid %||% "")
    bib[[length(bib) + 1]] <- Filter(function(v) !(is.character(v) && length(v) == 1 && !nzchar(v)), csl)
  }
}
res <- rbindlist(results)
fwrite(res, "manuscript/references_verification.csv")
jsonlite::write_json(bib, "manuscript/references.json", auto_unbox = TRUE, pretty = TRUE)   # 自動產生，請勿手改
print(res[, .(citation_key, status, pmid, year, journal, sim = title_similarity)], nrows = 100)
n_bad <- res[status %in% c("FAIL", "CHECK"), .N]
cat(sprintf("\n查證：%d 篇；通過 %d、需人工確認 %d、失敗 %d\n", nrow(res), res[grepl("^verified", status), .N],
            res[status == "CHECK", .N], res[status == "FAIL", .N]))
if (n_bad > 0) quit(status = 1)
