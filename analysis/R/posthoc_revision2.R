# 事後分析（post hoc）：回應 JCRP 第二輪審查（R2.2，Table 1 加權後的 SMD）。不在 SAP v1.0 內，論文須標明 post hoc。
# 主分析的傾向分數模型把年份當連續變項，重疊加權只讓兩組的「平均年份」完全相同，年代分布不一定相同。
# 這裡比較主模型與年份樣條模型（第一輪事後分析 P1）加權後的年代分布與 SMD。
# 輸出：results/posthoc_r2.csv（model × metric × group）
source("analysis/R/estimation.R")

era_balance <- function(model, fits) {
  per_imp <- rbindlist(Map(function(x, f) {
    d <- data.table(dual = x$dual, period = period_of(x$year, p$treatment_periods), w = f$weights)
    rbind(d[, .(metric = paste0("share_", period), value = sum(w)), keyby = .(dual, period)][
            , value := value / sum(value), by = dual][, .(metric, dual, value)],
          data.table(metric = "smd_period", dual = NA_integer_,
                     value = table1_smd(x, f$weights)[variable == "period", smd]))
  }, imputed, fits))
  per_imp[, .(value = mean(value)), by = .(metric, dual)][
    , .(model = model, metric, group = fcase(is.na(dual), "both", dual == 1, "dual", default = "single"), value)]
}
res <- rbind(era_balance("linear", run(imputed, "overlap", survival = FALSE)),
             era_balance("spline", run(imputed, "overlap", survival = FALSE, ps = PS_SPLINE)))
fwrite(res, file.path(RESULTS_DIR, "posthoc_r2.csv"))
print(dcast(res, metric ~ model + group, value.var = "value"))
write_provenance("posthoc_r2", file.path(RESULTS_DIR, "posthoc_r2.csv"),
                 pkgs = c("mice", "WeightIt", "tableone", "survey"))
