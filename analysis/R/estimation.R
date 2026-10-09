# 共用估計工具：資料讀取、多重插補（SAP §7）、重疊加權／配對／迴歸分析、Rubin 合併、存圖。
# 主分析（outcomes.R）與事後分析（posthoc_*.R）都 source 這個檔案，確保用同一份插補與同一套方法。

source("analysis/R/common.R")
source("analysis/R/definitions.R")
suppressPackageStartupMessages({
  library(mice); library(WeightIt); library(MatchIt); library(cobalt)
  library(survival); library(sandwich); library(EValue); library(ggplot2); library(patchwork)
})

p <- params()
a <- fread("data/derived/analysis.csv")
a[, `:=`(ecog = factor(ecog), ct = factor(ct, c("T1", "T2", "T3", "T4")), cn = factor(cn), grade = factor(grade, 1:3))]
OUTCOMES <- c("study_id", "pcr", "pcr_strict", "efs_days", "efs_event", "os_days", "os_event", "adjuvant_tdm1")
YEAR <- 365.25
ps_formula <- function(drop = character()) reformulate(setdiff(PS_COVARIATES, drop), "dual")

# ── 多重插補（SAP §7）：只用治療組與共變項，不含任何結果變項 ─────────────
imp <- mice(a[, c("dual", PS_COVARIATES), with = FALSE], m = p$imputation_m, seed = p$seeds$imputation,
            printFlag = FALSE)
imputed <- lapply(seq_len(p$imputation_m), function(i) cbind(as.data.table(complete(imp, i)), a[, ..OUTCOMES]))
complete_case <- list(a[complete.cases(a[, ..PS_COVARIATES])])

# Rubin 法則合併（m = 1 時即為單一分析）
pool_rubin <- function(est, v) {
  m <- length(est); qbar <- mean(est); W <- mean(v)
  B <- if (m > 1) var(est) else 0
  tot <- W + (1 + 1 / m) * B
  df <- if (B > 0) (m - 1) * (1 + W / ((1 + 1 / m) * B))^2 else Inf
  se <- sqrt(tot); q <- qt(0.975, df)
  list(est = qbar, se = se, lo = qbar - q * se, hi = qbar + q * se, p = 2 * pt(-abs(qbar / se), df))
}
coef_var <- function(fit, term = "dual", vc = vcov(fit)) {
  i <- match(term, names(coef(fit)))   # 有些模型的 vcov 沒有欄名，按位置取
  c(est = unname(coef(fit)[i]), var = unname(as.matrix(vc)[i, i]))
}
ess <- function(w, g) vapply(0:1, function(k) sum(w[g == k])^2 / sum(w[g == k]^2), 0)

# 加權 KM：指定時間點的存活率與標準誤、5 年 RMST
km_summary <- function(time, event, dual, w) {
  fit <- survfit(Surv(time / YEAR, event) ~ dual, weights = w, robust = TRUE, id = seq_along(time))
  s <- summary(fit, times = c(3, 5), extend = TRUE)
  rm <- summary(fit, rmean = 5)$table
  list(surv = matrix(s$surv, 2, byrow = TRUE, dimnames = list(c("single", "dual"), c("y3", "y5"))),
       se = matrix(s$std.err, 2, byrow = TRUE, dimnames = list(c("single", "dual"), c("y3", "y5"))),
       rmst_diff = unname(rm[2, "rmean"] - rm[1, "rmean"]), rmst_var = unname(rm[2, "se(rmean)"]^2 + rm[1, "se(rmean)"]^2),
       fit = fit)
}

# ── 一份資料、一種平衡方法的完整分析 ─────────────────────────────────────
analyze <- function(x, method = c("overlap", "match", "regression"), outcome = "pcr", drop = character(),
                    survival = TRUE) {
  method <- match.arg(method)
  f <- ps_formula(drop)
  out <- list(n = c(sum(x$dual == 0), sum(x$dual == 1)))
  events <- function(dt) dt[, .(efs = sum(efs_event), os = sum(os_event)), keyby = dual]
  if (method == "overlap") {
    w <- weightit(f, data = x, method = "glm", estimand = "ATO")
    x[, wt := w$weights]
    bal <- bal.tab(w, stats = "m", un = TRUE, s.d.denom = "pooled", binary = "std")$Balance
    bal <- bal[rownames(bal) != "prop.score", ]
    out$balance <- data.table(covariate = rownames(bal), before = bal$Diff.Un, after = bal$Diff.Adj)
    out$ess <- ess(x$wt, x$dual)
    m_or <- glm_weightit(reformulate("dual", outcome), data = x, weightit = w, family = binomial)
    m_rd <- glm_weightit(reformulate("dual", outcome), data = x, weightit = w, family = gaussian)
    out$or <- coef_var(m_or); out$rd <- coef_var(m_rd)
    out$prop <- x[, weighted.mean(get(outcome), wt), keyby = dual]$V1
    if (survival) {
      for (ep in c("efs", "os")) {
        cx <- coxph_weightit(as.formula(sprintf("Surv(%s_days, %s_event) ~ dual", ep, ep)), data = x, weightit = w)
        out[[paste0(ep, "_hr")]] <- coef_var(cx)
        out[[paste0(ep, "_km")]] <- km_summary(x[[paste0(ep, "_days")]], x[[paste0(ep, "_event")]], x$dual, x$wt)
        zph_fit <- coxph(as.formula(sprintf("Surv(%s_days, %s_event) ~ dual", ep, ep)), data = x, weights = wt,
                         robust = TRUE)
        out[[paste0(ep, "_ph_p")]] <- cox.zph(zph_fit)$table["GLOBAL", "p"]
      }
    }
  } else if (method == "match") {
    # 單標靶人數少於雙標靶，部分雙標靶病人必然配不到對（MatchIt 會警告，屬預期）
    m <- suppressWarnings(matchit(f, data = x, method = "nearest", caliper = 0.2, std.caliper = TRUE))
    md <- as.data.table(match.data(m))
    out$n <- c(sum(md$dual == 0), sum(md$dual == 1)); out$ess <- out$n
    out$events <- events(md)
    g_or <- glm(reformulate("dual", outcome), data = md, family = quasibinomial, weights = weights)
    g_rd <- lm(reformulate("dual", outcome), data = md, weights = weights)
    out$or <- coef_var(g_or, vc = vcovCL(g_or, cluster = ~subclass))
    out$rd <- coef_var(g_rd, vc = vcovCL(g_rd, cluster = ~subclass))
    out$prop <- md[, mean(get(outcome)), keyby = dual]$V1
    if (survival) {
      for (ep in c("efs", "os")) {
        cx <- coxph(as.formula(sprintf("Surv(%s_days, %s_event) ~ dual", ep, ep)), data = md, weights = weights,
                    cluster = subclass)
        out[[paste0(ep, "_hr")]] <- coef_var(cx)
      }
    }
  } else {
    g <- glm(update(f, as.formula(paste(outcome, "~ dual + ."))), data = x, family = binomial)
    out$or <- coef_var(g)
    out$prop <- x[, mean(get(outcome)), keyby = dual]$V1
    if (survival) {
      for (ep in c("efs", "os")) {
        cx <- coxph(update(f, as.formula(sprintf("Surv(%s_days, %s_event) ~ dual + .", ep, ep))), data = x)
        out[[paste0(ep, "_hr")]] <- coef_var(cx)
      }
    }
  }
  if (is.null(out$events)) out$events <- events(x)
  out
}

run <- function(datasets, ...) lapply(datasets, function(x) analyze(copy(x), ...))
pooled <- function(fits, key, transform = identity) {
  r <- pool_rubin(vapply(fits, function(f) f[[key]][["est"]], 0), vapply(fits, function(f) f[[key]][["var"]], 0))
  lapply(r[c("est", "lo", "hi")], transform) |> c(list(p = r$p))
}

# ── 圖：共用常數與存檔 ─────────────────────────────────────────────────────
dir.create(file.path(RESULTS_DIR, "figures"), showWarnings = FALSE, recursive = TRUE)
GROUPS <- c(dual = "Trastuzumab + pertuzumab", single = "Trastuzumab alone")
COLORS <- c(dual = "#2a78d6", single = "#eb6834")   # dataviz 驗證色盤第 1、2 色；另以線型區分
save_fig <- function(plot, name, w, h) {
  ggsave(file.path(RESULTS_DIR, "figures", paste0(name, ".pdf")), plot, width = w, height = h, device = cairo_pdf)
  ggsave(file.path(RESULTS_DIR, "figures", paste0(name, ".png")), plot, width = w, height = h, dpi = 200,
         device = ragg::agg_png)
}
