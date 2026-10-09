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

# ── 補充資料表格 ───────────────────────────────────────────────────────────
# Table S1：完整版基期特徵（results/table1.csv），依變項切成 ≤ max_rows 列的數段，每段重複表頭
supp_baseline_parts <- function(max_rows) {
  full <- rd_res("table1.csv", strip.white = FALSE, na.strings = c("", "NA"))
  starts <- which(!is.na(full$SMD))
  blocks <- split(seq_len(nrow(full)), findInterval(seq_len(nrow(full)), starts))
  parts <- list(); cur <- integer()
  for (b in blocks) {
    if (length(cur) + length(b) > max_rows) { parts[[length(parts) + 1]] <- cur; cur <- integer() }
    cur <- c(cur, b)
  }
  parts[[length(parts) + 1]] <- cur
  show <- copy(full)
  show[is.na(SMD), Characteristic := paste0("  ", Characteristic)]
  show[, SMD := ifelse(is.na(SMD), "", sprintf("%.2f", SMD))]
  lapply(seq_along(parts), function(i) list(
    title = sprintf("Table S1%s. Baseline characteristics, all categories (part %d of %d)", letters[i], i, length(parts)),
    data = show[parts[[i]]],
    footnotes = "Values are n (%) or median (IQR); missing values are shown and excluded from percentages. SMD, standardized mean difference before weighting."))
}

supp_subgroup <- function(tk = manuscript_tokens()) {
  sg <- rd_res("outcomes_subgroup.csv")
  list(title = "Table S2. Pathologic complete response by hormone receptor status (exploratory)",
       data = sg[, .(Subgroup = subgroup, `Patients, n (T+P/T)` = sprintf("%d/%d", n_dual, n_single),
                     `pCR, T+P*` = sprintf("%.1f%%", 100 * pcr_dual), `pCR, T*` = sprintf("%.1f%%", 100 * pcr_single),
                     `Odds ratio (95% CI)` = ci(or, or_lo, or_hi))],
       footnotes = sprintf("*Overlap-weighted proportions with propensity scores re-estimated within each subgroup, averaged over %s imputations. %s for interaction (overall weights). pCR, pathologic complete response; T, trastuzumab; T+P, trastuzumab plus pertuzumab.",
                           tk[["imputations"]], tk[["p_interaction_hr"]]))
}

supp_evalues <- function() {
  ev <- rd_res("outcomes_evalues.csv")
  list(title = "Table S3. E-values for unmeasured confounding",
       data = ev[, .(Endpoint = endpoint, `E-value, point estimate` = sprintf("%.2f", point),
                     `E-value, confidence limit` = ifelse(is.na(lower) & is.na(upper), "1.00†",
                                                          sprintf("%.2f", fifelse(is.na(lower), upper, lower))))],
       footnotes = "The E-value is the minimum strength of association, on the risk-ratio scale, that an unmeasured confounder would need to have with both treatment and outcome to explain away the observed estimate. †The confidence interval includes the null value.")
}

# Table S4：回應第一輪審查的事後分析（analysis/R/posthoc_revision1.R）
supp_posthoc <- function() {
  ph <- rd_res("posthoc_r1.csv")
  list(title = "Table S4. Post hoc analyses performed in response to peer review",
       data = ph[, .(Analysis = label, `Patients, n (T+P/T)` = sprintf("%d/%d", n_dual, n_single), Measure = measure,
                     `Estimate (95% CI)` = ci(est, lo, hi), P = pval(p))],
       footnotes = "These analyses were not prespecified in the statistical analysis plan. All used overlap weighting with the same 20 imputations as the primary analysis. Patients operated on elsewhere were assigned to groups by pertuzumab use within 180 days of the index date. CI, confidence interval; EFS, event-free survival; HR, hazard ratio; OR, odds ratio; OS, overall survival; pCR, pathologic complete response; T, trastuzumab; T+P, trastuzumab plus pertuzumab.")
}

supplementary_tables <- function(max_rows) c(supp_baseline_parts(max_rows), list(supp_subgroup(), supp_evalues(), supp_posthoc()))
