# 論文數字代號：{{name}} → 由 results/ 的機器可讀檔與 config.toml 產生的字串。論文裡的數字一律用代號，不手打。
# 格式依 manuscript/journal.yaml：比例附絕對人數、效應值附 95% CI、P 值為斜體大寫 P 加精確值。
suppressPackageStartupMessages(library(data.table))
source("analysis/R/common.R")   # study_facts()

fmt_pct <- function(x, d = 1) sprintf(paste0("%.", d, "f%%"), 100 * x)
# 區間：下限為負時用 "to" 與真正的負號，避免「-1.7–39.3」被誤讀
ci_range <- function(lo, hi, d = 2) {
  f <- function(x) sub("^-", "−", sprintf(paste0("%.", d, "f"), x))
  paste0(f(lo), ifelse(lo < 0, " to ", "–"), f(hi))
}
fmt_ci <- function(est, lo, hi, d = 2) sprintf("%s (95%% CI, %s)", sprintf(paste0("%.", d, "f"), est), ci_range(lo, hi, d))
fmt_p <- function(p) if (p >= 0.001) sprintf("*P* = %.3f", p) else sprintf("*P* = %s", formatC(p, format = "g", digits = 2))
fmt_n_of <- function(k, n) sprintf("%d/%d (%.1f%%)", k, n, 100 * k / n)
fmt_month <- function(d) format(as.Date(d), "%B %Y")
# JCRP：1 到 10 的數字用英文拼寫
spell <- function(n) if (n >= 0 && n <= 10 && n == round(n)) c("zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten")[n + 1] else as.character(n)

manuscript_tokens <- function() {
  facts <- study_facts()
  rf <- function(f) fread(file.path(RESULTS_DIR, f))
  flow <- rf("cohort_flow.csv"); pcr <- rf("outcomes_pcr.csv"); sv <- rf("outcomes_survival.csv")
  de <- rf("outcomes_descriptive.csv"); sg <- rf("outcomes_subgroup.csv"); ev <- rf("outcomes_evalues.csv")
  bal <- rf("outcomes_balance.csv"); t1 <- fread(file.path(RESULTS_DIR, "table1_manuscript.csv"), colClasses = "character"); prov <- jsonlite::read_json(file.path(RESULTS_DIR, "provenance", "outcomes.json"))
  fl <- function(st, rs = NULL) flow[step == st & (is.null(rs) | reason %in% rs), sum(n)]
  d1 <- function(it, g) de[item == it & group == g, value]
  P <- function(k) pcr[analysis == k]
  S <- function(ep, k) sv[endpoint == ep & analysis == k]

  tk <- list(
    # 研究期間與收案（config.toml、cohort_flow.csv）
    enroll_start = fmt_month(facts$enroll_start), enroll_end = fmt_month(facts$enroll_end),
    fu_cutoff = sprintf("%s %d, %s", format(as.Date(facts$fu_cutoff), "%B"), as.integer(format(as.Date(facts$fu_cutoff), "%d")),
                        format(as.Date(facts$fu_cutoff), "%Y")),
    n_records = fl("records"), n_duplicates = spell(fl("duplicates")), n_patients = fl("patients"),
    n_excl_stage = fl("excluded_1", "Clinical stage 0-I"), n_excl_m1 = fl("excluded_1", "Distant metastasis at diagnosis"),
    n_excl_her2 = fl("excluded_1", "HER2 not positive"),
    n_excl_no_orders = fl("excluded_2", "No systemic therapy orders at our hospital"),
    n_excl_surgery_elsewhere = fl("excluded_3", "Surgery at another hospital, no pathology report"),
    n_cohort = fl("cohort"), n_dual = d1("n", "dual"), n_single = d1("n", "single"),
    median_fu = sprintf("%.1f", d1("median_followup_years", "all")),
    median_fu_dual = sprintf("%.1f", d1("median_followup_years", "dual")),
    median_fu_single = sprintf("%.1f", d1("median_followup_years", "single")),
    # 平衡
    ess_dual = round(P("main")$ess_dual), ess_single = round(P("main")$ess_single),
    max_smd_after = sprintf("%.3f", max(bal$max_abs_after)), max_smd_before = sprintf("%.2f", max(abs(bal$smd_before))),
    # 與 Table 1 一致：年份為三個時段的類別變項（平衡圖則為連續年份，數值不同屬正常）
    smd_period_table1 = t1[grepl("^Year of", characteristic), smd],
    smd_anthracycline_table1 = t1[grepl("^Anthracycline", characteristic), smd],
    # pCR（主要終點）
    pcr_crude_dual = fmt_n_of(d1("pcr_n", "dual"), d1("n", "dual")),
    pcr_crude_single = fmt_n_of(d1("pcr_n", "single"), d1("n", "single")),
    pcr_w_dual = fmt_pct(P("main")$pcr_dual), pcr_w_single = fmt_pct(P("main")$pcr_single),
    pcr_rd = sprintf("%.1f percentage points (95%% CI, %s)", 100 * P("main")$rd,
                     ci_range(100 * P("main")$rd_lo, 100 * P("main")$rd_hi, 1)),
    pcr_or = fmt_ci(P("main")$or, P("main")$or_lo, P("main")$or_hi), pcr_p = fmt_p(P("main")$p),
    evalue_pcr = sprintf("%.2f", ev[endpoint == "pCR (OR)", point]),
    evalue_pcr_ci = sprintf("%.2f", ev[endpoint == "pCR (OR)", lower]),
    # pCR 敏感度與次族群
    pcr_or_s1 = fmt_ci(P("S1")$or, P("S1")$or_lo, P("S1")$or_hi), pcr_or_s2 = fmt_ci(P("S2")$or, P("S2")$or_lo, P("S2")$or_hi),
    pcr_or_s3 = fmt_ci(P("S3")$or, P("S3")$or_lo, P("S3")$or_hi), pcr_or_s4 = fmt_ci(P("S4")$or, P("S4")$or_lo, P("S4")$or_hi),
    pcr_or_s6 = fmt_ci(P("S6")$or, P("S6")$or_lo, P("S6")$or_hi),
    n_s1_dual = P("S1")$n_dual, n_s1_single = P("S1")$n_single, n_s2_pairs = P("S2")$n_dual,
    or_hr_negative = fmt_ci(sg[subgroup == "Hormone receptor negative", or], sg[subgroup == "Hormone receptor negative", or_lo],
                            sg[subgroup == "Hormone receptor negative", or_hi]),
    or_hr_positive = fmt_ci(sg[subgroup == "Hormone receptor positive", or], sg[subgroup == "Hormone receptor positive", or_lo],
                            sg[subgroup == "Hormone receptor positive", or_hi]),
    p_interaction_hr = fmt_p(sg$p_interaction[1]),
    # EFS／OS
    efs_events_dual = S("EFS", "main")$events_dual, efs_events_single = S("EFS", "main")$events_single,
    efs_hr = fmt_ci(S("EFS", "main")$hr, S("EFS", "main")$hr_lo, S("EFS", "main")$hr_hi), efs_p = fmt_p(S("EFS", "main")$p),
    efs_5y_dual = fmt_pct(S("EFS", "main")$s5_dual), efs_5y_single = fmt_pct(S("EFS", "main")$s5_single),
    os_events_dual = S("OS", "main")$events_dual, os_events_single = S("OS", "main")$events_single,
    os_hr = fmt_ci(S("OS", "main")$hr, S("OS", "main")$hr_lo, S("OS", "main")$hr_hi), os_p = fmt_p(S("OS", "main")$p),
    os_5y_dual = fmt_pct(S("OS", "main")$s5_dual), os_5y_single = fmt_pct(S("OS", "main")$s5_single),
    efs_ph_p = fmt_p(S("EFS", "main")$ph_p), os_ph_p = fmt_p(S("OS", "main")$ph_p),
    tdm1_non_pcr_dual = fmt_pct(d1("adjuvant_tdm1_pct_non_pcr", "dual") / 100),
    tdm1_non_pcr_single = fmt_pct(d1("adjuvant_tdm1_pct_non_pcr", "single") / 100),
    # 各治療年代的未加權 pCR（描述性）
    pcr_2012_2015_dual = fmt_n_of(d1("pcr_n_period", "dual_2012_2015"), d1("n_period", "dual_2012_2015")),
    pcr_2012_2015_single = fmt_n_of(d1("pcr_n_period", "single_2012_2015"), d1("n_period", "single_2012_2015")),
    pcr_2016_2019_dual = fmt_n_of(d1("pcr_n_period", "dual_2016_2019"), d1("n_period", "dual_2016_2019")),
    pcr_2016_2019_single = fmt_n_of(d1("pcr_n_period", "single_2016_2019"), d1("n_period", "single_2016_2019")),
    pcr_2020_2023_all = fmt_n_of(sum(de[item == "pcr_n_period" & grepl("2020_2023", group), value]),
                                 sum(de[item == "n_period" & grepl("2020_2023", group), value])),
    n_2020_2023_single = spell(d1("n_period", "single_2020_2023")),
    # 軟體（provenance）
    r_version = sub("^R version ([0-9.]+).*$", "\\1", prov$r_version),
    imputations = params()$imputation_m
  )
  vapply(tk, as.character, "")
}

# {{name}} 換成數值；{{name|b}} 把信賴區間的圓括號改成方括號（用在圓括號裡面時，避免括號套括號）。
# 未知代號一律報錯（避免印出錯字或空白）
fill_tokens <- function(text, tokens = manuscript_tokens()) {
  used <- unique(regmatches(text, gregexpr("\\{\\{[a-z0-9_]+(\\|b)?\\}\\}", text))[[1]])
  names_used <- sub("\\|b$", "", gsub("[{}]", "", used))
  unknown <- setdiff(names_used, names(tokens))
  if (length(unknown)) stop("未知的數字代號：", paste0("{{", unique(unknown), "}}", collapse = "、"))
  for (i in seq_along(used)) {
    value <- tokens[[names_used[i]]]
    if (grepl("\\|b\\}\\}$", used[i])) value <- sub("\\((95% CI, [^)]*)\\)", "[\\1]", value)
    text <- gsub(used[i], value, text, fixed = TRUE)
  }
  text
}
