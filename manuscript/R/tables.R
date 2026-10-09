# 論文表格：只讀 results/ 的機器可讀檔並排版，不做任何計算以外的分析。
# 每張表回傳 list(title, data, footnotes)；article.qmd 排版、check.R 檢查列數與欄數（manuscript/journal.yaml）。
suppressPackageStartupMessages(library(data.table))
source("manuscript/R/tokens.R")

rd_res <- function(f, ...) fread(file.path(RESULTS_DIR, f), ...)
num <- function(x, d = 2) ifelse(is.na(x), "", sprintf(paste0("%.", d, "f"), x))
ci <- function(est, lo, hi, d = 2) ifelse(is.na(est), "", sprintf("%s (%s)", sprintf(paste0("%.", d, "f"), est), ci_range(lo, hi, d)))
pval <- function(p) ifelse(is.na(p), "", ifelse(p >= 0.001, sprintf("%.3f", p), formatC(p, format = "g", digits = 2)))
events <- function(x) ifelse(abs(x - round(x)) < 1e-9, sprintf("%d", as.integer(round(x))), sprintf("%.1f‡", x))

ANALYSIS_LABELS <- c(main = "Overlap weighting (primary)", S1 = "S1: Treatment start 2016–2019 only",
                     S2 = "S2: 1:1 propensity-score matching", S3 = "S3: Multivariable regression",
                     S4 = "S4: pCR defined as ypT0 ypN0", S6 = "S6: Complete cases")

table_baseline <- function(tk = manuscript_tokens()) {
  d <- rd_res("table1_manuscript.csv", colClasses = "character", strip.white = FALSE, na.strings = NULL)
  miss <- rd_res("table1_manuscript_missing.csv")
  setnames(d, c("characteristic", "smd"), c("Characteristic", "SMD†"))
  list(
    title = "Table 1. Baseline characteristics of the study cohort, by neoadjuvant anti-HER2 regimen",
    data = d,
    footnotes = c(
      "Values are n (%) unless otherwise indicated. Abbreviations: BMI, body mass index; ECOG, Eastern Cooperative Oncology Group; ER, estrogen receptor; HER2, human epidermal growth factor receptor 2; IHC, immunohistochemistry; IQR, interquartile range; ISH, in situ hybridization; LVEF, left ventricular ejection fraction; PR, progesterone receptor; SMD, standardized mean difference.",
      sprintf("*Missing: histologic grade, %d; Ki-67, %d. Percentages exclude missing values.",
              miss[item == "grade_missing", value], miss[item == "ki67_missing", value]),
      sprintf("†Before weighting. After overlap weighting, every covariate in the propensity-score model was exactly balanced (maximum absolute SMD, %s).", tk[["max_smd_after"]])
    ))
}

table_pcr <- function() {
  p <- rd_res("outcomes_pcr.csv"); de <- rd_res("outcomes_descriptive.csv")
  g <- function(it, grp) de[item == it & group == grp, value]
  crude <- data.table(
    Analysis = "Unweighted", `Patients, n (T+P/T)` = sprintf("%d/%d", g("n", "dual"), g("n", "single")),
    `pCR, T+P` = sprintf("%d (%.1f)", g("pcr_n", "dual"), 100 * g("pcr_n", "dual") / g("n", "dual")),
    `pCR, T` = sprintf("%d (%.1f)", g("pcr_n", "single"), 100 * g("pcr_n", "single") / g("n", "single")),
    `Risk difference, percentage points (95% CI)` = "", `Odds ratio (95% CI)` = "", P = "")
  adj <- p[match(names(ANALYSIS_LABELS), analysis)][, .(
    Analysis = ANALYSIS_LABELS[analysis],
    `Patients, n (T+P/T)` = sprintf("%d/%d", n_dual, n_single),
    `pCR, T+P` = ifelse(is.na(pcr_dual), "", sprintf("%.1f%%*", 100 * pcr_dual)),
    `pCR, T` = ifelse(is.na(pcr_single), "", sprintf("%.1f%%*", 100 * pcr_single)),
    `Risk difference, percentage points (95% CI)` = ci(100 * rd, 100 * rd_lo, 100 * rd_hi, 1),
    `Odds ratio (95% CI)` = ci(or, or_lo, or_hi), P = pval(p))]
  list(
    title = "Table 2. Pathologic complete response: primary and sensitivity analyses",
    data = rbind(crude, adj),
    footnotes = c(
      "Unweighted row: n (%) of patients with pCR. Abbreviations: CI, confidence interval; pCR, pathologic complete response (ypT0/is ypN0; isolated tumor cells in lymph nodes were not considered pCR); T, trastuzumab; T+P, trastuzumab plus pertuzumab.",
      "*Weighted (overlap weighting) or matched proportions, averaged over 20 imputations; no absolute counts correspond to weighted proportions.",
      "S3 adjusts for the propensity-score covariates by regression and has no corresponding weighted proportions or risk difference."
    ))
}

table_survival <- function() {
  s <- rd_res("outcomes_survival.csv")
  block <- function(ep, label) {
    x <- s[endpoint == ep][match(c("main", "S1", "S2", "S3", "S6"), analysis)]
    rbind(data.table(Analysis = label, `Events, n (T+P/T)` = "", `Hazard ratio (95% CI)` = "", P = "",
                     `5-year rate, T+P` = "", `5-year rate, T` = ""),
          x[, .(Analysis = paste0("  ", ANALYSIS_LABELS[analysis]),
                `Events, n (T+P/T)` = sprintf("%s/%s", events(events_dual), events(events_single)),
                `Hazard ratio (95% CI)` = ci(hr, hr_lo, hr_hi), P = pval(p),
                `5-year rate, T+P` = ifelse(is.na(s5_dual), "", sprintf("%.1f%%*", 100 * s5_dual)),
                `5-year rate, T` = ifelse(is.na(s5_single), "", sprintf("%.1f%%*", 100 * s5_single)))])
  }
  list(
    title = "Table 3. Event-free and overall survival",
    data = rbind(block("EFS", "Event-free survival†"), block("OS", "Overall survival")),
    footnotes = c(
      "Abbreviations: CI, confidence interval; T, trastuzumab; T+P, trastuzumab plus pertuzumab.",
      "*Weighted Kaplan-Meier estimates, averaged over 20 imputations.",
      "†Events: progression precluding surgery, locoregional recurrence, distant metastasis, or death from any cause.",
      "‡Matched analysis: mean number of events across imputations."
    ))
}

manuscript_tables <- function() list(table_baseline(), table_pcr(), table_survival())
