# Table 1：符合收案條件者的基期特徵，依治療組比較（只含治療前特徵，不含任何療效結果）。
# 兩組差異以標準化差異（SMD）呈現；|SMD| < 0.1 視為平衡。
# 輸入：data/derived/cohort.csv、registry.csv。輸出：
#   results/table1.csv   機器可讀（論文自動帶入）
#   results/table1.docx  預覽用（Word）
source("analysis/R/common.R")
source("analysis/R/definitions.R")
suppressPackageStartupMessages({
  library(gtsummary)
  library(flextable)
})

DERIVED_DIR <- "data/derived"
p <- params()
rd <- function(k) fread(file.path(DERIVED_DIR, paste0(k, ".csv")), colClasses = "character", na.strings = NULL)

co <- rd("cohort")[eligible == "TRUE"]
reg <- unique(rd("registry"))
d <- merge(co, reg, by = "study_id")
stopifnot(nrow(d) == nrow(co))

cut <- p$receptor_positive_cutoff
periods <- vapply(p$treatment_periods, function(x) sprintf("%d–%d", x[1], x[2]), "")
period_of <- function(y) {
  i <- vapply(y, function(v) which(vapply(p$treatment_periods, function(x) v >= x[1] && v <= x[2], TRUE))[1], 1L)
  factor(periods[i], periods)
}

# 共變項編碼與傾向分數模型共用（definitions.R build_covariates），這裡只轉成顯示用的標籤
cv <- build_covariates(d, cut)
tab <- data.table(
  group = factor(fifelse(d$treatment_group == "dual", "Trastuzumab + pertuzumab", "Trastuzumab alone"),
                 c("Trastuzumab + pertuzumab", "Trastuzumab alone")),
  age = cv$age,
  menopause = factor(cv$postmenopausal, 0:1, c("Premenopausal", "Postmenopausal")),
  ecog = cv$ecog,
  bmi = cv$bmi,
  lvef = cv$lvef,
  ct = cv$ct,
  cn = cv$cn,
  stage = factor(d$stage_ajcc8, p$eligibility$stages),
  hr = factor(cv$hr_positive, 1:0, c("Positive", "Negative")),
  her2 = factor(cv$her2_ihc3, 1:0, c("IHC 3+", "IHC 2+, ISH amplified")),
  grade = cv$grade,
  ki67 = cv$ki67,
  backbone = factor(d$chemo_backbone, c("Anthracycline-based", "Carboplatin-based", "Taxane only", "Other")),
  period = period_of(cv$year)
)
tab[, backbone := droplevels(backbone)]

labels <- list(
  age ~ "Age at diagnosis, years", menopause ~ "Menopausal status", ecog ~ "ECOG performance status",
  bmi ~ "BMI, kg/m²", lvef ~ "Baseline LVEF, %", ct ~ "Clinical T category", cn ~ "Clinical N category",
  stage ~ "Clinical stage (AJCC 8th, anatomic)",
  hr ~ sprintf("Hormone receptor (ER or PR ≥%g%%)", cut), her2 ~ "HER2 status",
  grade ~ "Histologic grade", ki67 ~ "Ki-67, %", backbone ~ "Neoadjuvant chemotherapy backbone",
  period ~ "Year of neoadjuvant therapy start"
)

t1 <- tbl_summary(tab, by = group, label = labels, missing = "ifany", missing_text = "Missing",
                  statistic = list(all_continuous() ~ "{median} ({p25}–{p75})", all_categorical() ~ "{n} ({p}%)"),
                  digits = list(all_continuous() ~ 1, all_categorical() ~ c(0, 1))) |>
  add_overall(last = FALSE) |>
  add_difference(test = everything() ~ "smd", estimate_fun = everything() ~ label_style_number(digits = 2)) |>
  modify_column_hide(any_of(c("conf.low", "conf.high"))) |>
  modify_header(label = "**Characteristic**", estimate = "**SMD**") |>
  modify_footnote_header("Median (IQR) or n (%).", columns = all_stat_cols()) |>
  modify_footnote_header("Standardized mean difference; |SMD| < 0.1 indicates balance.", columns = "estimate") |>
  modify_source_note("Carboplatin-based: carboplatin without an anthracycline.") |>
  remove_abbreviation("CI = Confidence Interval")

n_err <- unresolved_errors()
caption <- paste0(
  "Table 1. Baseline characteristics by neoadjuvant anti-HER2 regimen",
  if (n_err > 0) sprintf(" [PRELIMINARY: %d data-validation errors pending]", n_err), ". Synthetic data for teaching.")

out <- as_tibble(t1, col_labels = TRUE)
names(out) <- gsub("\\s*\n\\s*", " ", gsub("\\*\\*", "", names(out)))
fwrite(as.data.table(out), file.path(RESULTS_DIR, "table1.csv"))
# 直式 A4／Letter 可用寬約 6.5 吋：特徵 2.3、三個統計欄各 1.25、SMD 0.6
ft <- as_flex_table(t1) |> set_caption(caption) |> fontsize(size = 8, part = "all") |>
  padding(padding.top = 1, padding.bottom = 1, part = "all") |> line_spacing(space = 1, part = "all") |>
  width(j = 1, width = 2.3) |> width(j = 2:4, width = 1.25) |> width(j = 5, width = 0.6) |>
  height_all(height = 0.175, part = "body") |> hrule(rule = "exact", part = "body") |>
  set_table_properties(layout = "fixed")
save_as_docx(ft, path = file.path(RESULTS_DIR, "table1.docx"),
             pr_section = officer::prop_section(page_margins = officer::page_mar(top = 0.6, bottom = 0.6)))

write_provenance("table1", c("results/table1.csv", "results/table1.docx"), pkgs = c("gtsummary", "flextable", "smd"))
smd <- t1$table_body[!is.na(t1$table_body$estimate) & t1$table_body$row_type == "label", c("label", "estimate")]
cat(sprintf("Table 1：%d 人（%s）→ results/table1.{csv,docx}；|SMD| ≥ 0.1 的變項：%s\n", nrow(tab),
            paste(sprintf("%s %d", levels(tab$group), as.integer(table(tab$group))), collapse = "、"),
            paste(sprintf("%s (%.2f)", smd$label, smd$estimate)[abs(smd$estimate) >= 0.1], collapse = "、")))

# ── 論文版 Table 1（JCRP：≤ 25 列、≤ 10 欄）────────────────────────────────
# 合併細項以符合列數限制；完整版（上方 table1.docx）作為補充資料。SMD 以 tableone 計算（多分類變項用 Yang & Dalton 法）。
ms <- data.table(
  dual = tab$group == "Trastuzumab + pertuzumab",
  age = cv$age, postmenopausal = cv$postmenopausal == 1, ecog_ge1 = cv$ecog != "0", bmi = cv$bmi, lvef = cv$lvef,
  ct = cv$ct, cn = cv$cn, hr_positive = cv$hr_positive == 1, her2_ihc3 = cv$her2_ihc3 == 1,
  grade3 = fifelse(is.na(cv$grade), NA, cv$grade == "3"), ki67 = cv$ki67,
  anthracycline = cv$anthracycline == 1, period = tab$period)
smd_of <- function(v) {
  t1 <- tableone::CreateTableOne(vars = v, strata = "dual", data = as.data.frame(ms[, c("dual", v), with = FALSE]),
                                 test = FALSE, smd = TRUE)
  unname(tableone::ExtractSmd(t1)[1, 1])
}
fmt_cont <- function(x) sprintf("%.1f (%.1f–%.1f)", median(x, na.rm = TRUE), quantile(x, .25, na.rm = TRUE),
                                quantile(x, .75, na.rm = TRUE))
fmt_bin <- function(x) sprintf("%d (%.1f)", sum(x, na.rm = TRUE), 100 * mean(x, na.rm = TRUE))
row <- function(label, f, v, smd = TRUE) data.table(
  characteristic = label, dual = f(ms[dual == TRUE][[v]]), single = f(ms[dual == FALSE][[v]]),
  smd = if (smd) sprintf("%.2f", smd_of(v)) else "")
level_rows <- function(header, v) {
  lv <- levels(ms[[v]])
  rbind(data.table(characteristic = header, dual = "", single = "", smd = sprintf("%.2f", smd_of(v))),
        rbindlist(lapply(lv, function(l) data.table(
          characteristic = paste0("  ", l), dual = fmt_bin(ms[dual == TRUE][[v]] == l),
          single = fmt_bin(ms[dual == FALSE][[v]] == l), smd = ""))))
}
t1_ms <- rbind(
  row("Age at diagnosis, years, median (IQR)", fmt_cont, "age"),
  row("Postmenopausal", fmt_bin, "postmenopausal"),
  row("ECOG performance status ≥1", fmt_bin, "ecog_ge1"),
  row("BMI, kg/m², median (IQR)", fmt_cont, "bmi"),
  row("Baseline LVEF, %, median (IQR)", fmt_cont, "lvef"),
  level_rows("Clinical T category", "ct"),
  level_rows("Clinical N category", "cn"),
  row(sprintf("Hormone receptor positive (ER or PR ≥%g%%)", cut), fmt_bin, "hr_positive"),
  row("HER2 IHC 3+ (vs IHC 2+, ISH amplified)", fmt_bin, "her2_ihc3"),
  row("Histologic grade 3*", fmt_bin, "grade3"),
  row("Ki-67, %, median (IQR)*", fmt_cont, "ki67"),
  row("Anthracycline-based chemotherapy", fmt_bin, "anthracycline"),
  level_rows("Year of neoadjuvant therapy start", "period")
)
setnames(t1_ms, c("dual", "single"), c(sprintf("Trastuzumab + pertuzumab (n = %d)", sum(ms$dual)),
                                       sprintf("Trastuzumab alone (n = %d)", sum(!ms$dual))))
fwrite(t1_ms, file.path(RESULTS_DIR, "table1_manuscript.csv"))
fwrite(data.table(item = c("grade_missing", "ki67_missing", "age_missing"),
                  value = c(sum(is.na(ms$grade3)), sum(is.na(ms$ki67)), sum(is.na(ms$age)))),
       file.path(RESULTS_DIR, "table1_manuscript_missing.csv"))
write_provenance("table1_manuscript", c("results/table1_manuscript.csv", "results/table1_manuscript_missing.csv"),
                 pkgs = c("tableone"))
