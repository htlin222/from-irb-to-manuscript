# 事後分析（post hoc）：回應 JCRP 第一輪審查意見。不在 SAP v1.0 內，論文與決定紀錄須標明 post hoc。
# 方法與主分析相同（同一份多重插補、重疊加權、Rubin 合併；analysis/R/estimation.R）。
# 輸出：results/posthoc_r1.csv（效應值）、posthoc_r1_overlap.csv（傾向分數重疊）、posthoc_r1_timing.csv（時間零點），
#       results/figures/ps_overlap.{pdf,png}
source("analysis/R/estimation.R")
suppressPackageStartupMessages(library(splines))

rd <- function(k) fread(file.path("data/derived", paste0(k, ".csv")), colClasses = "character", na.strings = NULL)
co <- rd("cohort"); su <- rd("surgery"); fu <- rd("followup"); reg <- unique(rd("registry"))
pbs_ids <- fu[recurrence_type == "Progression before surgery" & !study_id %in% su$study_id, study_id]
row <- function(id, label, fits, key, transform = exp, measure) {
  r <- pooled(fits, key, transform)
  data.table(id = id, label = label, measure = measure, n_dual = fits[[1]]$n[2], n_single = fits[[1]]$n[1],
             est = r$est, lo = r$lo, hi = r$hi, p = r$p)
}
out <- list()

# ── R1.1 兩組的傾向分數是否重疊；年份改用樣條 ───────────────────────────────
ps_by_imp <- sapply(imputed, function(x) weightit(ps_formula(), data = x, method = "glm", estimand = "ATO")$ps)
ov <- data.table(study_id = imputed[[1]]$study_id, dual = imputed[[1]]$dual, year = imputed[[1]]$year,
                 ps = rowMeans(ps_by_imp))
ov[, w := fifelse(dual == 1, 1 - ps, ps)]   # 重疊權重（以平均傾向分數計，僅供描述）
period <- function(y) fcase(y <= 2015, "2012-2015", y <= 2019, "2016-2019", default = "2020-2023")
overlap <- rbind(
  ov[, .(metric = "ps_median", value = median(ps)), keyby = .(group = fifelse(dual == 1, "dual", "single"))],
  ov[, .(metric = "ps_q1", value = quantile(ps, .25)), keyby = .(group = fifelse(dual == 1, "dual", "single"))],
  ov[, .(metric = "ps_q3", value = quantile(ps, .75)), keyby = .(group = fifelse(dual == 1, "dual", "single"))],
  # 共同支持區：落在另一組傾向分數範圍內的比例
  data.table(group = "dual", metric = "in_common_support",
             value = ov[dual == 1, mean(ps >= ov[dual == 0, min(ps)] & ps <= ov[dual == 0, max(ps)])]),
  data.table(group = "single", metric = "in_common_support",
             value = ov[dual == 0, mean(ps >= ov[dual == 1, min(ps)] & ps <= ov[dual == 1, max(ps)])]),
  ov[, .(metric = "weight_share", value = sum(w) / ov[, sum(w)]), keyby = .(group = period(year))]
)
spline_f <- reformulate(c(setdiff(PS_COVARIATES, "year"), "ns(year, 3)"), "dual")
out$P1 <- row("P1", "Propensity score with natural spline for year (3 df)",
              run(imputed, "overlap", survival = FALSE, ps = spline_f), "or", measure = "OR for pCR")

# ── R1.2 術後 T-DM1：只看 T-DM1 普及前（2012–2019）開始治療者的 EFS ─────────
pre <- lapply(imputed, function(x) x[year <= 2019])
fits_pre <- run(pre, "overlap")
out$P2 <- row("P2", "EFS, treatment start 2012-2019 (before adjuvant T-DM1 was used)", fits_pre, "efs_hr",
              measure = "HR for EFS")
tdm1_pre <- a[year <= 2019 & pcr == 0, .(value = 100 * mean(adjuvant_tdm1)), keyby = .(group = fifelse(dual == 1, "dual", "single"))]

# ── R1.3 沒有病理結果者的處理 ─────────────────────────────────────────────
no_pbs <- lapply(imputed, function(x) x[!study_id %in% pbs_ids])
out$P3 <- row("P3", "pCR excluding patients with progression before surgery", run(no_pbs, "overlap", survival = FALSE),
              "or", measure = "OR for pCR")
# 他院手術而排除者：依指標日起 180 天內有無 pertuzumab 歸組，pCR 分別假設全有／全無
ex <- co[step3 != "", .(study_id, index_d = as.IDate(index_d))]
ch <- rd("chemo")[, order_d := as_date(order_date)][study_id %in% ex$study_id]
pseudo_surgery <- ex[, .(study_id, surg_d = index_d + 181L)]   # 只用來界定 180 天的術前期間
neo_ex <- neoadjuvant_summary(map_orders(ch, drug_map()), pseudo_surgery, fu[0, .(study_id, recurrence_type, rec_d = as.IDate(character()))])
dx <- merge(merge(neo_ex[, .(study_id, chemo_backbone, index_d, dual = as.integer(neo_pertuzumab))], reg, by = "study_id"),
            data.table(study_id = ex$study_id), by = "study_id")
cov_ex <- cbind(dx[, .(study_id, dual)], build_covariates(dx, p$receptor_positive_cutoff))
bound <- function(assumed) {
  aa <- rbind(a[, c("study_id", "dual", PS_COVARIATES, "pcr"), with = FALSE],
              cbind(cov_ex, pcr = assumed), fill = TRUE)
  aa[, `:=`(ecog = factor(ecog), ct = factor(ct, c("T1", "T2", "T3", "T4")), cn = factor(cn), grade = factor(grade, 1:3))]
  im <- mice(aa[, c("dual", PS_COVARIATES), with = FALSE], m = p$imputation_m, seed = p$seeds$imputation, printFlag = FALSE)
  lapply(seq_len(p$imputation_m), function(i) cbind(as.data.table(complete(im, i)), aa[, .(study_id, pcr)]))
}
out$P4 <- row("P4", "pCR including patients operated elsewhere, all assumed pCR", run(bound(1L), "overlap", survival = FALSE),
              "or", measure = "OR for pCR")
out$P5 <- row("P5", "pCR including patients operated elsewhere, all assumed no pCR", run(bound(0L), "overlap", survival = FALSE),
              "or", measure = "OR for pCR")

# ── R2.2 限制在 5 年內的存活比較 ───────────────────────────────────────────
cap5 <- lapply(imputed, function(x) {
  x <- copy(x)
  x[, `:=`(efs_event = as.integer(efs_event == 1 & efs_days <= 5 * YEAR), efs_days = pmin(efs_days, 5 * YEAR),
           os_event = as.integer(os_event == 1 & os_days <= 5 * YEAR), os_days = pmin(os_days, 5 * YEAR))]
})
fits5 <- run(cap5, "overlap")
out$P6 <- row("P6", "EFS with follow-up truncated at 5 years", fits5, "efs_hr", measure = "HR for EFS")
out$P7 <- row("P7", "OS with follow-up truncated at 5 years", fits5, "os_hr", measure = "HR for OS")

res <- rbindlist(out)
fwrite(res, file.path(RESULTS_DIR, "posthoc_r1.csv"))
fwrite(rbind(overlap, tdm1_pre[, .(group, metric = "tdm1_pct_non_pcr_2012_2019", value)],
             data.table(group = c("dual", "single"), metric = "n_operated_elsewhere", value = c(sum(cov_ex$dual), sum(1 - cov_ex$dual))),
             data.table(group = c("dual", "single"), metric = "n_progression_before_surgery",
                        value = c(a[study_id %in% pbs_ids, sum(dual)], a[study_id %in% pbs_ids, sum(1 - dual)]))),
       file.path(RESULTS_DIR, "posthoc_r1_overlap.csv"))

# ── R2.1 時間零點與不死時間：pertuzumab 何時加入、單標靶組最早何時惡化或手術 ──
cs <- co[eligible == "TRUE", .(study_id, treatment_group, index_d = as.IDate(index_d), window_end = as.IDate(window_end))]
om <- map_orders(rd("chemo")[, order_d := as_date(order_date)][study_id %in% cs$study_id], drug_map())
pz <- merge(om[agent == "pertuzumab"], cs[treatment_group == "dual"], by = "study_id")[
  order_d >= index_d & order_d <= window_end, .(start_day = as.numeric(min(order_d) - min(index_d))), by = study_id]
single_end <- merge(cs[treatment_group == "single"], a[, .(study_id)], by = "study_id")[, .(day = as.numeric(window_end - index_d + 1))]
timing <- data.table(
  metric = c("dual_n", "dual_pertuzumab_from_index", "dual_pertuzumab_later", "dual_pertuzumab_later_median_day",
             "single_min_days_to_surgery_or_progression", "single_n_before_day_84"),
  value = c(nrow(pz), pz[start_day == 0, .N], pz[start_day > 0, .N], pz[start_day > 0, median(start_day)],
            single_end[, min(day)], single_end[day < 84, .N]))
fwrite(timing, file.path(RESULTS_DIR, "posthoc_r1_timing.csv"))

# ── 圖：兩組傾向分數分布 ───────────────────────────────────────────────────
ov[, group := factor(fifelse(dual == 1, "dual", "single"), c("dual", "single"))]
g <- ggplot(ov, aes(ps, colour = group, fill = group)) +
  geom_histogram(aes(y = after_stat(density)), binwidth = 0.025, boundary = 0, alpha = 0.25, position = "identity",
                 linewidth = 0.3) +
  scale_colour_manual(values = COLORS, labels = GROUPS, name = NULL) +
  scale_fill_manual(values = COLORS, labels = GROUPS, name = NULL) +
  scale_x_continuous("Propensity score for trastuzumab plus pertuzumab (mean over imputations)", limits = c(0, 1),
                     breaks = seq(0, 1, 0.2), expand = expansion(0)) +
  labs(y = "Density", caption = "Post hoc. Synthetic data for teaching.") +
  theme_classic(base_size = 10) +
  theme(legend.position = "top", legend.justification = "left",
        plot.caption = element_text(size = 7.5, colour = "grey30", hjust = 0))
save_fig(g, "ps_overlap", 6.5, 4)

write_provenance("posthoc_r1", file.path(RESULTS_DIR, c("posthoc_r1.csv", "posthoc_r1_overlap.csv", "posthoc_r1_timing.csv")),
                 pkgs = c("mice", "WeightIt", "survival", "ggplot2"))
print(res[, .(id, measure, n_dual, n_single, est = round(est, 2), lo = round(lo, 2), hi = round(hi, 2), p = round(p, 3))])
print(overlap); print(timing); print(tdm1_pre)
