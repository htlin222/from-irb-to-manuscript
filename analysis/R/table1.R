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
