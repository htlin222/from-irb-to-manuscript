# 主分析與敏感度分析（依 analysis/SAP.md v1.0，tag sap-v1.0）。
# 輸入 data/derived/analysis.csv；輸出 results/outcomes_*.csv 與 results/figures/（km_*, love_plot）。
source("analysis/R/estimation.R")   # 資料、多重插補、analyze()、pooled()、save_fig()

analyses <- list(
  main = list(label = "Primary: overlap weighting", fits = run(imputed, "overlap")),
  S1 = list(label = "S1: 2016-2019 only, overlap weighting",
            fits = run(lapply(imputed, function(x) x[year >= 2016 & year <= 2019]), "overlap")),
  S2 = list(label = "S2: 1:1 propensity-score matching", fits = run(imputed, "match")),
  S3 = list(label = "S3: multivariable regression", fits = run(imputed, "regression")),
  S4 = list(label = "S4: pCR defined as ypT0 ypN0", fits = run(imputed, "overlap", outcome = "pcr_strict",
                                                                 survival = FALSE)),
  S6 = list(label = "S6: complete cases, overlap weighting", fits = run(complete_case, "overlap"))
)

# ── 結果表 ─────────────────────────────────────────────────────────────────
pcr_tab <- rbindlist(lapply(names(analyses), function(k) {
  fits <- analyses[[k]]$fits
  or <- pooled(fits, "or", exp)
  rd <- if (!is.null(fits[[1]]$rd)) pooled(fits, "rd") else list(est = NA, lo = NA, hi = NA)
  prop <- rowMeans(vapply(fits, `[[`, c(0, 0), "prop"))
  e <- if (!is.null(fits[[1]]$ess)) rowMeans(vapply(fits, `[[`, c(0, 0), "ess")) else c(NA, NA)
  data.table(analysis = k, label = analyses[[k]]$label,
             n_dual = fits[[1]]$n[2], n_single = fits[[1]]$n[1], ess_dual = e[2], ess_single = e[1],
             pcr_dual = prop[2], pcr_single = prop[1], rd = rd$est, rd_lo = rd$lo, rd_hi = rd$hi,
             or = or$est, or_lo = or$lo, or_hi = or$hi, p = or$p)
}))
pcr_tab[analysis == "S3", c("pcr_dual", "pcr_single") := NA]   # 迴歸調整沒有對應的「調整後比例」

surv_tab <- rbindlist(lapply(c("efs", "os"), function(ep) rbindlist(lapply(setdiff(names(analyses), "S4"), function(k) {
  fits <- analyses[[k]]$fits
  hr <- pooled(fits, paste0(ep, "_hr"), exp)
  evn <- rowMeans(vapply(fits, function(f) f$events[[ep]], c(0, 0)))   # 配對時各插補略有不同，取平均
  row <- data.table(endpoint = toupper(ep), analysis = k, label = analyses[[k]]$label,
                    events_dual = evn[2], events_single = evn[1],
                    hr = hr$est, hr_lo = hr$lo, hr_hi = hr$hi, p = hr$p)
  km <- fits[[1]][[paste0(ep, "_km")]]
  if (!is.null(km)) {
    s <- Reduce(`+`, lapply(fits, function(f) f[[paste0(ep, "_km")]]$surv)) / length(fits)
    rm <- pool_rubin(vapply(fits, function(f) f[[paste0(ep, "_km")]]$rmst_diff, 0),
                     vapply(fits, function(f) f[[paste0(ep, "_km")]]$rmst_var, 0))
    row[, `:=`(s3_dual = s["dual", "y3"], s3_single = s["single", "y3"], s5_dual = s["dual", "y5"],
               s5_single = s["single", "y5"], rmst5_diff = rm$est, rmst5_lo = rm$lo, rmst5_hi = rm$hi,
               ph_p = median(vapply(fits, `[[`, 0, paste0(ep, "_ph_p"))))]
  }
  row
}), fill = TRUE)), fill = TRUE)

balance <- rbindlist(lapply(analyses$main$fits, `[[`, "balance"))[
  , .(smd_before = mean(before), smd_after = mean(after), max_abs_after = max(abs(after))), by = covariate]

# Table 1 加權後的 SMD（期刊第二輪 R2.2）：與 Table 1 相同的變項定義與 tableone 算法（多分類變項用 Yang & Dalton 法），
# 在每組插補資料以主分析的重疊權重計算，再取 20 組的平均
smd_weighted <- rbindlist(Map(function(x, f) table1_smd(x, f$weights), imputed, analyses$main$fits))[
  , .(smd_after = mean(smd)), by = variable]

# 次族群（SAP §6.4）：依荷爾蒙受體分層，各層內重新估計傾向分數；交互作用用整體權重
subgroup <- rbindlist(lapply(0:1, function(h) {
  fits <- run(lapply(imputed, function(x) x[hr_positive == h]), "overlap", drop = "hr_positive", survival = FALSE)
  or <- pooled(fits, "or", exp)
  data.table(subgroup = if (h == 1) "Hormone receptor positive" else "Hormone receptor negative",
             n_dual = fits[[1]]$n[2], n_single = fits[[1]]$n[1],
             pcr_dual = mean(vapply(fits, function(f) f$prop[2], 0)), pcr_single = mean(vapply(fits, function(f) f$prop[1], 0)),
             or = or$est, or_lo = or$lo, or_hi = or$hi)
}))
inter <- pool_rubin(
  vapply(imputed, function(x) {
    w <- weightit(ps_formula(), data = x, method = "glm", estimand = "ATO")
    coef(glm_weightit(pcr ~ dual * hr_positive, data = x, weightit = w, family = binomial))["dual:hr_positive"]
  }, 0),
  vapply(imputed, function(x) {
    w <- weightit(ps_formula(), data = x, method = "glm", estimand = "ATO")
    vcov(glm_weightit(pcr ~ dual * hr_positive, data = x, weightit = w, family = binomial))["dual:hr_positive", "dual:hr_positive"]
  }, 0))
subgroup[, p_interaction := inter$p]

# E-value（SAP S5）
main_pcr <- pcr_tab[analysis == "main"]; main_efs <- surv_tab[endpoint == "EFS" & analysis == "main"]
efs_rare <- mean(a$efs_event) < 0.15
evals <- rbind(
  data.table(endpoint = "pCR (OR)", t(evalues.OR(main_pcr$or, main_pcr$or_lo, main_pcr$or_hi, rare = FALSE)["E-values", ])),
  data.table(endpoint = "EFS (HR)", t(evalues.HR(main_efs$hr, main_efs$hr_lo, main_efs$hr_hi, rare = efs_rare)["E-values", ])),
  fill = TRUE)

# 描述性：追蹤時間中位數（反向 KM）、術後 T-DM1 使用（SAP §8 說明）
rev_km <- survfit(Surv(os_days / YEAR, 1 - os_event) ~ 1, data = a)
rev_km_g <- survfit(Surv(os_days / YEAR, 1 - os_event) ~ dual, data = a)
descriptive <- rbind(
  data.table(item = "median_followup_years", group = "all", value = unname(summary(rev_km)$table["median"])),
  data.table(item = "median_followup_years", group = c("single", "dual"), value = unname(summary(rev_km_g)$table[, "median"])),
  a[, .(item = "adjuvant_tdm1_pct", group = fifelse(dual == 1, "dual", "single"), value = 100 * mean(adjuvant_tdm1)),
    keyby = dual][, .(item, group, value)],
  a[pcr == 0, .(item = "adjuvant_tdm1_pct_non_pcr", group = fifelse(dual == 1, "dual", "single"),
                value = 100 * mean(adjuvant_tdm1)), keyby = dual][, .(item, group, value)],
  data.table(item = "efs_events_rare_assumption", group = "all", value = as.numeric(efs_rare)),
  # 未加權的實際人數（JCRP：百分比須附上計算它的絕對人數）
  a[, .(item = "n", group = fifelse(dual == 1, "dual", "single"), value = .N), keyby = dual][, .(item, group, value)],
  a[, .(item = "pcr_n", group = fifelse(dual == 1, "dual", "single"), value = sum(pcr)), keyby = dual][, .(item, group, value)],
  a[, .(item = "pcr_strict_n", group = fifelse(dual == 1, "dual", "single"), value = sum(pcr_strict)), keyby = dual][, .(item, group, value)],
  # 依治療開始年份分期的未加權人數（描述性：說明未加權與加權結果差異的來源）
  rbindlist(lapply(p$treatment_periods, function(yr) a[year >= yr[1] & year <= yr[2],
    .(item = c("n_period", "pcr_n_period"), value = c(.N, sum(pcr))), keyby = dual][
    , .(item, group = sprintf("%s_%d_%d", fifelse(dual == 1, "dual", "single"), yr[1], yr[2]), value)]))
)

fwrite(pcr_tab, file.path(RESULTS_DIR, "outcomes_pcr.csv"))
fwrite(surv_tab, file.path(RESULTS_DIR, "outcomes_survival.csv"))
fwrite(balance, file.path(RESULTS_DIR, "outcomes_balance.csv"))
fwrite(smd_weighted, file.path(RESULTS_DIR, "table1_smd_weighted.csv"))
fwrite(subgroup, file.path(RESULTS_DIR, "outcomes_subgroup.csv"))
fwrite(evals, file.path(RESULTS_DIR, "outcomes_evalues.csv"))
fwrite(descriptive, file.path(RESULTS_DIR, "outcomes_descriptive.csv"))

# ── 圖 ─────────────────────────────────────────────────────────────────────
km_plot <- function(ep, ylab) {
  fits <- analyses$main$fits
  at_risk <- function(t) a[, .(n = sum(get(paste0(ep, "_days")) / YEAR >= t)), keyby = dual]
  # 只畫到兩組都還有 ≥ 10% 病人在追蹤的整數年；之後的尾端人數太少、不可靠
  xmax <- max(Filter(function(t) all(at_risk(t)$n >= 0.1 * a[, .N, keyby = dual]$N), 0:20))
  grid <- seq(0, xmax, by = 0.02)
  curve <- rbindlist(lapply(fits, function(f) {
    s <- summary(f[[paste0(ep, "_km")]]$fit, times = grid, extend = TRUE)
    data.table(t = s$time, surv = s$surv, dual = as.integer(sub("dual=", "", s$strata)))
  }))[, .(surv = mean(surv)), by = .(dual, t)]
  curve[, group := factor(fifelse(dual == 1, "dual", "single"), c("dual", "single"))]
  r <- surv_tab[endpoint == toupper(ep) & analysis == "main"]
  lab_t <- round(xmax * 0.55, 1)   # 直接標示組名：雙標靶標在曲線上方、單標靶標在下方
  labs_dt <- curve[abs(t - lab_t) < 1e-9][, vj := fifelse(group == "dual", -0.9, 1.9)]
  g <- ggplot(curve, aes(t, surv, colour = group, linetype = group)) +
    geom_step(linewidth = 0.7) +
    geom_text(data = labs_dt, aes(label = GROUPS[as.character(group)], vjust = vj), hjust = 0.5, size = 3,
              colour = "grey20", show.legend = FALSE) +
    annotate("text", x = 0.2, y = 0.08, hjust = 0, size = 3.1, colour = "grey20",
             label = sprintf("Overlap-weighted HR %.2f (95%% CI %.2f–%.2f)", r$hr, r$hr_lo, r$hr_hi)) +
    scale_colour_manual(values = COLORS, labels = GROUPS, name = NULL) +
    scale_linetype_manual(values = c(dual = "solid", single = "22"), labels = GROUPS, name = NULL) +
    scale_y_continuous(ylab, limits = c(0, 1), labels = scales::percent, expand = expansion(0)) +
    scale_x_continuous("Years since start of neoadjuvant therapy", limits = c(0, xmax), breaks = 0:xmax,
                       expand = expansion(add = c(0.3, 0.3))) +
    theme_classic(base_size = 10) +
    theme(legend.position = "top", legend.justification = "left", legend.key.width = unit(1.4, "lines"),
          axis.line = element_line(linewidth = 0.4, colour = "grey40"), axis.ticks = element_line(colour = "grey40"))
  risk <- rbindlist(lapply(0:xmax, function(t) at_risk(t)[, t := t]))
  risk[, group := factor(fifelse(dual == 1, "dual", "single"), c("single", "dual"))]
  tbl <- ggplot(risk, aes(t, group, label = n)) + geom_text(size = 2.9, colour = "grey20") +
    scale_y_discrete(labels = GROUPS, name = NULL) +
    scale_x_continuous(NULL, limits = c(0, xmax), breaks = 0:xmax, expand = expansion(add = c(0.3, 0.3))) +
    labs(title = "Number at risk") + theme_void(base_size = 9) +
    theme(axis.text.y = element_text(hjust = 1, colour = "grey20"), plot.title = element_text(size = 8.5, colour = "grey30"))
  (g / tbl + plot_layout(heights = c(5, 1))) +
    plot_annotation(caption = "Weighted Kaplan-Meier curves averaged over 20 imputations. Synthetic data for teaching.",
                    theme = theme(plot.caption = element_text(size = 7.5, colour = "grey30", hjust = 0)))
}
save_fig(km_plot("efs", "Event-free survival"), "km_efs", 6.5, 5)
save_fig(km_plot("os", "Overall survival"), "km_os", 6.5, 5)

lp <- balance[, .(covariate, Unweighted = smd_before, `Overlap-weighted` = smd_after)] |>
  melt(id.vars = "covariate", variable.name = "sample", value.name = "smd")
COVARIATE_LABELS <- c(age = "Age", postmenopausal = "Postmenopausal", bmi = "BMI", lvef = "Baseline LVEF",
                      hr_positive = "Hormone receptor positive", her2_ihc3 = "HER2 IHC 3+", ki67 = "Ki-67",
                      anthracycline = "Anthracycline-based chemotherapy", year = "Year of treatment start (continuous)")
pretty_cov <- function(x) {
  out <- COVARIATE_LABELS[x]
  out[is.na(out)] <- sub("^ecog_", "ECOG ", sub("^ct_", "Clinical ", sub("^cn_", "Clinical ", sub("^grade_", "Grade ", x[is.na(out)]))))
  unname(out)
}
lp[, covariate := factor(pretty_cov(covariate), pretty_cov(balance[order(abs(smd_before)), covariate]))]
love <- ggplot(lp, aes(abs(smd), covariate, shape = sample, colour = sample)) +
  geom_vline(xintercept = 0.1, linetype = "22", colour = "grey50") + geom_point(size = 2.4) +
  scale_colour_manual(values = c(Unweighted = "#eb6834", `Overlap-weighted` = "#2a78d6"), name = NULL) +
  scale_shape_manual(values = c(Unweighted = 1, `Overlap-weighted` = 16), name = NULL) +
  labs(x = "Absolute standardized mean difference", y = NULL,
       caption = "Dashed line: 0.1. Averaged over 20 imputations. Synthetic data for teaching.") +
  theme_classic(base_size = 10) + theme(legend.position = "top", legend.justification = "left",
                                        plot.caption = element_text(size = 7.5, colour = "grey30", hjust = 0))
save_fig(love, "love_plot", 6, 5.5)

write_provenance("outcomes", c(file.path(RESULTS_DIR, c("outcomes_pcr.csv", "outcomes_survival.csv", "outcomes_balance.csv", "table1_smd_weighted.csv",
                                                         "outcomes_subgroup.csv", "outcomes_evalues.csv",
                                                         "outcomes_descriptive.csv")),
                               file.path(RESULTS_DIR, "figures", c("km_efs.pdf", "km_os.pdf", "love_plot.pdf"))),
                 pkgs = c("mice", "WeightIt", "MatchIt", "cobalt", "survival", "EValue", "ggplot2", "patchwork", "tableone", "survey"))
cat(sprintf("主分析：pCR OR %.2f (%.2f–%.2f)；EFS HR %.2f (%.2f–%.2f)；OS HR %.2f (%.2f–%.2f)\n",
            main_pcr$or, main_pcr$or_lo, main_pcr$or_hi, main_efs$hr, main_efs$hr_lo, main_efs$hr_hi,
            surv_tab[endpoint == "OS" & analysis == "main", hr], surv_tab[endpoint == "OS" & analysis == "main", hr_lo],
            surv_tab[endpoint == "OS" & analysis == "main", hr_hi]))
