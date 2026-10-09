# IRB 結案文件的數字與內容（make closure-report）。
# 輸入：結案報告.md（文字＋{{代號}}）、results/、config.toml、manuscript/meta.yaml。輸出：
#   results/irb_closure.md    結案報告書（SF038）各節內容，數字已填入 → config.toml closure.report
#   results/irb_closure.toml  實際收案人數與各組人數 → config.toml subjects.actual_n、subjects.groups 的 n
source("manuscript/R/tokens.R")

cfg <- RcppTOML::parseTOML("config.toml")
meta <- yaml::read_yaml("manuscript/meta.yaml")
tk <- as.list(manuscript_tokens())

# 論文（期刊接受刊登）：作者依 meta.yaml，格式同論文參考文獻（Vancouver）
initials <- function(name) {
  parts <- strsplit(name, " ")[[1]]
  family <- parts[length(parts)]
  given <- paste(substr(unlist(strsplit(parts[-length(parts)], "-")), 1, 1), collapse = "")
  paste(family, given)
}
authors <- vapply(meta$authors, function(a) initials(a$name_en), "")
tk$publication <- sprintf("%s. %s. J Cancer Res Pract. Accepted for publication. (Fictional, teaching demo.)",
                          paste(authors, collapse = ", "), cfg$study$title_en)
tk$data_period <- cfg$dates$data_period
tk$planned_n <- cfg$subjects$planned_n

writeLines(fill_tokens(paste(readLines("結案報告.md", encoding = "UTF-8"), collapse = "\n"), tk),
           file.path(RESULTS_DIR, "irb_closure.md"))

# 收案人數（與論文的收案流程圖同一來源：results/cohort_flow.csv、outcomes_descriptive.csv）
writeLines(c(
  "# 由 make closure-report（analysis/R/irb_closure.R）產生，請勿手改。",
  sprintf("actual_n = %d", as.integer(tk$n_cohort)),
  sprintf("n_dual = %d", as.integer(tk$n_dual)),
  sprintf("n_single = %d", as.integer(tk$n_single))),
  file.path(RESULTS_DIR, "irb_closure.toml"))
write_provenance("irb_closure", file.path(RESULTS_DIR, c("irb_closure.md", "irb_closure.toml")), pkgs = character())
cat(sprintf("結案報告內容已寫入 results/irb_closure.md（實際收案 %s 人）\n", tk$n_cohort))
