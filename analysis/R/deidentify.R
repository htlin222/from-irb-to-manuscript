# 第一步：去識別化。原始資料 → data/derived/（研究編號取代病歷號；生日換成診斷年齡後刪除）。
# 對照表（chart_no ↔ study_id）存在 params$linkage_dir，不在專案資料夾內。
# 已存在的對照表沿用（同一病人永遠同一研究編號），新病人才配新編號（隨機順序）。
source("analysis/R/common.R")

DERIVED_DIR <- "data/derived"

manifest <- verify_manifest()
p <- params()
raw <- read_all_raw(p)$raw

link_dir <- path.expand(p$linkage_dir)
link_file <- file.path(link_dir, "linkage.csv")
dir.create(link_dir, showWarnings = FALSE, mode = "0700")
Sys.chmod(link_dir, "0700")

ids <- unique(unlist(lapply(raw, `[[`, "chart_no")))
link <- if (file.exists(link_file)) fread(link_file, colClasses = "character") else
  data.table(chart_no = character(), study_id = character())
new <- setdiff(ids, link$chart_no)
if (length(new)) {
  used <- as.integer(sub("^P", "", link$study_id))
  pool <- setdiff(seq_len(length(ids) + length(link$chart_no)), used)
  link <- rbind(link, data.table(chart_no = sample(new), study_id = sprintf("P%04d", pool[seq_along(new)])))
  fwrite(link, link_file)
}
Sys.chmod(link_file, "0600")

deid <- function(dt) {
  out <- merge(dt, link, by = "chart_no", sort = FALSE)
  stopifnot(nrow(out) == nrow(dt))
  out[, chart_no := NULL]
  setcolorder(out, "study_id")
  out[]
}

reg <- deid(raw$registry)
birth <- as_date(reg$birth_date)
reg[, age_at_dx := fifelse(year(birth) <= p$birth_placeholder_max_year, NA_real_,
                           round(as.numeric(as_date(dx_date) - birth) / 365.25, 1))]
reg[, birth_date := NULL]

out <- list(registry = reg, chemo = deid(raw$chemo), surgery = deid(raw$surgery), followup = deid(raw$followup))
dir.create(DERIVED_DIR, showWarnings = FALSE, recursive = TRUE, mode = "0700")
Sys.chmod(DERIVED_DIR, "0700")
for (k in names(out)) {
  stopifnot(!any(c("chart_no", "birth_date") %in% names(out[[k]])))
  fwrite(out[[k]], file.path(DERIVED_DIR, paste0(k, ".csv")))
}
cat(sprintf("去識別化完成：%d 位病人 → %s（對照表：%s）\n", length(ids), DERIVED_DIR, link_file))
