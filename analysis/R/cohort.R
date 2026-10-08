# 收案流程：依計畫書的納入／排除條件逐步篩選，產生收案流程圖。
# 輸入：data/derived/（去識別化後）。輸出：
#   data/derived/cohort.csv               每位病人的收案判定與分組（不進 git）
#   results/cohort_flow.csv               每一步的人數（給程式與論文讀）
#   results/figures/cohort_flow.{pdf,png} 收案流程圖
# 資料檢查（results/data_validation.csv）若仍有「錯誤」，圖與表標示為暫定。
source("analysis/R/common.R")
source("analysis/R/definitions.R")
suppressPackageStartupMessages(library(grid))

DERIVED_DIR <- "data/derived"
p <- params()
facts <- study_facts()
rd <- function(k) fread(file.path(DERIVED_DIR, paste0(k, ".csv")), colClasses = "character", na.strings = NULL)

# ── 讀入與清理（清理規則見資料檢查報告 B1） ───────────────────────────────
reg_rows <- rd("registry")
reg <- unique(reg_rows)
if (anyDuplicated(reg$study_id)) stop("癌登同一病人有內容不一致的重複登錄，請先處理（資料檢查 B2）")
reg[, age_at_dx := as.numeric(age_at_dx)]

ch <- rd("chemo")[, order_d := as_date(order_date)]
su <- rd("surgery")[, surg_d := as_date(surgery_date)]
fu <- rd("followup")[, rec_d := as_date(recurrence_date)]
neo <- neoadjuvant_summary(map_orders(ch, drug_map()), su, fu)
co <- merge(reg, neo, by = "study_id", all.x = TRUE)

# ── 逐步篩選：每人只記第一個不符合的理由 ─────────────────────────────────
el <- p$eligibility
co[, step1 := fcase(cM == "M1" | stage_ajcc8 == "IV", "Distant metastasis at diagnosis",
                    !stage_ajcc8 %in% el$stages, "Clinical stage 0-I",
                    !her2_positive(HER2_IHC, HER2_ISH), "HER2 not positive",
                    !is.na(age_at_dx) & age_at_dx < el$min_age, sprintf("Age < %d years", el$min_age),
                    default = NA_character_)]
co[is.na(step1), step2 := fcase(
  is.na(index_d), "No systemic therapy orders at our hospital",
  upfront_surgery, "Surgery before systemic therapy",
  !is.na(window_end) & !(neo_trastuzumab & neo_chemo), "Neoadjuvant regimen without chemotherapy + trastuzumab",
  !is.na(window_end) & neo_tdm1, "Neoadjuvant T-DM1",
  index_d < facts$enroll_start | index_d > facts$enroll_end, "Neoadjuvant therapy started outside enrolment period",
  default = NA_character_)]
co[is.na(step1) & is.na(step2), step3 := fifelse(
  is.na(window_end), "No surgery at our hospital and no progression before surgery", NA_character_)]
co[, eligible := is.na(step1) & is.na(step2) & is.na(step3)]
stopifnot(co[eligible == TRUE, all(treatment_group %in% c("dual", "single"))])

fwrite(co[, .(study_id, eligible, step1, step2, step3, treatment_group, index_d, surg_d, window_end)],
       file.path(DERIVED_DIR, "cohort.csv"))

# ── 人數表 ─────────────────────────────────────────────────────────────────
count_reasons <- function(col, step) co[!is.na(get(col)), .N, by = .(reason = get(col))][
  , .(step = step, reason, n = N)][order(-n)]
flow <- rbind(
  data.table(step = "records", reason = "Registry records", n = nrow(reg_rows)),
  data.table(step = "duplicates", reason = "Duplicate registry records removed", n = nrow(reg_rows) - nrow(reg)),
  data.table(step = "patients", reason = "Unique patients", n = nrow(reg)),
  count_reasons("step1", "excluded_1"),
  data.table(step = "tumour_eligible", reason = "Stage II-III, HER2-positive", n = co[is.na(step1), .N]),
  count_reasons("step2", "excluded_2"),
  data.table(step = "neoadjuvant", reason = "Neoadjuvant chemotherapy + trastuzumab", n = co[is.na(step1) & is.na(step2), .N]),
  count_reasons("step3", "excluded_3"),
  data.table(step = "cohort", reason = "Eligible cohort", n = co[eligible == TRUE, .N]),
  co[eligible == TRUE, .N, by = .(reason = treatment_group)][
    , .(step = "group", reason = fifelse(reason == "dual", "Trastuzumab + pertuzumab", "Trastuzumab alone"), n = N)][
    order(-reason)]
)
val <- fread(file.path(RESULTS_DIR, "data_validation.csv"))
n_err <- val[level == "error", .N]
flow[, preliminary := n_err > 0]
fwrite(flow, file.path(RESULTS_DIR, "cohort_flow.csv"))

# ── 流程圖（CONSORT 格式，英文以便直接用於論文） ───────────────────────────
n_of <- function(s, r = NULL) flow[step == s & (is.null(r) | reason %in% r), sum(n)]
# 排除框：標題一行，每個理由一個項目符號，過長自動換行（續行縮排）
bullets <- function(s, mark = character()) {
  r <- flow[step == s]
  wrapped <- unlist(lapply(seq_len(nrow(r)), function(i) {
    w <- strwrap(paste0(r$reason[i], if (r$reason[i] %in% mark) "†"), width = 44)
    w[length(w)] <- sprintf("%s (n = %d)", w[length(w)], r$n[i])   # 人數不拆行
    c(paste0("• ", w[1]), if (length(w) > 1) paste0("   ", w[-1]))
  }))
  c(sprintf("Excluded (n = %d)", sum(r$n)), wrapped)
}
fmt_d <- function(x) format(x, "%b %Y")

draw_flow <- function() {
  grid.newpage()
  pushViewport(viewport(xscale = c(0, 100), yscale = c(0, 100)))
  fs <- 8.5; line_h <- 1.9; pad <- 1.4; arrow_len <- unit(1.6, "mm")
  height <- function(lines) pad + line_h * length(lines)
  box <- function(x, top, w, lines, left = FALSE, bold = FALSE) {
    h <- height(lines)
    grid.rect(x, top - h / 2, w, h, default.units = "native", gp = gpar(fill = "white", col = "black", lwd = 0.8))
    tx <- if (left) x - w / 2 + 1.2 else x
    for (i in seq_along(lines)) {
      grid.text(lines[i], tx, top - pad / 2 - line_h * (i - 0.5), default.units = "native",
                just = c(if (left) "left" else "centre", "centre"),
                gp = gpar(fontsize = fs, fontface = if (bold) "bold" else "plain"))
    }
    c(top = top, bottom = top - h, left = x - w / 2, mid = top - h / 2)
  }
  seg <- function(x, y, arrow = FALSE) {
    grid.lines(x, y, default.units = "native", gp = gpar(fill = "black", lwd = 0.8),
               arrow = if (arrow) arrow(length = arrow_len, type = "closed"))
  }

  mx <- 31; mw <- 44; sx <- 76; sw <- 40; gap <- 2.6
  main <- list(
    c("HER2-positive breast cancer in the cancer registry", sprintf("(n = %d records)", n_of("records"))),
    sprintf("Unique patients (n = %d)", n_of("patients")),
    c("Clinical stage II-III, HER2-positive", sprintf("(n = %d)", n_of("tumour_eligible"))),
    c("Neoadjuvant chemotherapy + trastuzumab started",
      sprintf("%s to %s (n = %d)", fmt_d(facts$enroll_start), fmt_d(facts$enroll_end), n_of("neoadjuvant"))),
    sprintf("Eligible cohort (n = %d)", n_of("cohort"))
  )
  side <- list(
    sprintf("Duplicate records removed (n = %d)", n_of("duplicates")),
    bullets("excluded_1"),
    bullets("excluded_2"),
    bullets("excluded_3", mark = "No surgery at our hospital and no progression before surgery")
  )

  y <- 98
  prev <- NULL
  for (i in seq_along(main)) {
    if (!is.null(prev)) {
      sh <- height(side[[i - 1]])
      s_top <- prev[["bottom"]] - gap
      sb <- box(sx, s_top, sw, side[[i - 1]], left = TRUE)
      seg(c(mx, sb[["left"]]), rep(sb[["mid"]], 2), arrow = TRUE)
      y <- s_top - sh - gap
      seg(c(mx, mx), c(prev[["bottom"]], y), arrow = TRUE)
    }
    prev <- box(mx, y, mw, main[[i]], bold = i == length(main))
  }

  gx <- c(mx - 14, mx + 14); gw <- 26
  split_y <- prev[["bottom"]] - gap / 2
  g_top <- prev[["bottom"]] - gap
  seg(c(mx, mx), c(prev[["bottom"]], split_y)); seg(gx, rep(split_y, 2))
  groups <- list(c("Trastuzumab + pertuzumab", sprintf("(n = %d)", n_of("group", "Trastuzumab + pertuzumab"))),
                 c("Trastuzumab alone", sprintf("(n = %d)", n_of("group", "Trastuzumab alone"))))
  for (k in 1:2) {
    seg(rep(gx[k], 2), c(split_y, g_top), arrow = TRUE)
    g <- box(gx[k], g_top, gw, groups[[k]])
  }

  notes <- c(
    if (n_err > 0) sprintf("PRELIMINARY: %d data-validation errors pending verification (results/data_validation.md).", n_err),
    "† May have had surgery at another hospital; pending verification.",
    "Other active malignancy and clinical-trial participation are not recorded in the extract.",
    "Synthetic data for teaching."
  )
  n_top <- g[["bottom"]] - gap
  for (i in seq_along(notes)) {
    grid.text(notes[i], 4, n_top - line_h * (i - 0.5), default.units = "native", just = c("left", "centre"),
              gp = gpar(fontsize = 7.5, fontface = if (n_err > 0 && i == 1) "bold" else "plain"))
  }
  popViewport()
}

dir.create(file.path(RESULTS_DIR, "figures"), showWarnings = FALSE, recursive = TRUE)
cairo_pdf(file.path(RESULTS_DIR, "figures", "cohort_flow.pdf"), width = 7.5, height = 9)
draw_flow(); invisible(dev.off())
ragg::agg_png(file.path(RESULTS_DIR, "figures", "cohort_flow.png"), width = 7.5, height = 9, units = "in", res = 200)
draw_flow(); invisible(dev.off())

cat(sprintf("收案：%d 人符合條件（雙標靶 %d、單標靶 %d）%s → results/figures/cohort_flow.png\n",
            n_of("cohort"), n_of("group", "Trastuzumab + pertuzumab"), n_of("group", "Trastuzumab alone"),
            if (n_err > 0) sprintf("［暫定：資料檢查尚有 %d 項錯誤］", n_err) else ""))
