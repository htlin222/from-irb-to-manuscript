# 分析資料集：收案名單中每位病人一列，含治療組、治療前特徵（SAP §4）、pCR、EFS、OS、術後 T-DM1。
# 所有定義都來自 definitions.R。輸出 data/derived/analysis.csv（去識別化，不進 git）。
source("analysis/R/common.R")
source("analysis/R/definitions.R")

DERIVED_DIR <- "data/derived"
p <- params()
facts <- study_facts()
rd <- function(k) fread(file.path(DERIVED_DIR, paste0(k, ".csv")), colClasses = "character", na.strings = NULL)

co <- rd("cohort")[eligible == "TRUE"]
reg <- unique(rd("registry"))
su <- rd("surgery")[, surg_d := as_date(surgery_date)]
fu <- rd("followup")[, `:=`(rec_d = as_date(recurrence_date), death_d = as_date(death_date),
                            last_d = as_date(last_contact_date))]
ch <- drop_unexecuted_orders(rd("chemo")[, order_d := as_date(order_date)], fu)
om <- map_orders(ch, drug_map())

d <- Reduce(function(a, b) merge(a, b, by = "study_id", all.x = TRUE), list(
  co[, .(study_id, treatment_group, chemo_backbone, index_d)],
  reg,
  su[, .(study_id, surg_d, ypT, ypN)],
  fu[, .(study_id, recurrence_type, rec_d, death_d, last_d)],
  ch[, .(last_order_d = max(order_d)), by = study_id]
))
stopifnot(nrow(d) == nrow(co))
d[, index_d := as.IDate(index_d)]
d[, end_d := followup_end(last_d, last_order_d, death_d, facts$fu_cutoff)]

tdm1_after <- merge(om[agent == "trastuzumab_emtansine", .(study_id, order_d)], su[, .(study_id, surg_d)],
                    by = "study_id")[order_d > surg_d, unique(study_id)]

out <- cbind(
  d[, .(study_id, dual = as.integer(treatment_group == "dual"),
        pcr = as.integer(pcr(ypT, ypN, had_surgery = !is.na(surg_d))),
        pcr_strict = as.integer(pcr(ypT, ypN, had_surgery = !is.na(surg_d), ypt = "ypT0")),
        adjuvant_tdm1 = as.integer(study_id %in% tdm1_after))],
  build_covariates(d, p$receptor_positive_cutoff),
  setnames(efs(d$index_d, d$recurrence_type, d$rec_d, d$death_d, d$end_d), c("efs_days", "efs_event")),
  setnames(os(d$index_d, d$death_d, d$end_d), c("os_days", "os_event"))
)
stopifnot(all(out$efs_days >= 0), all(out$os_days >= 0), !anyNA(out$dual))
fwrite(out, file.path(DERIVED_DIR, "analysis.csv"))
cat(sprintf("分析資料集：%d 人（雙標靶 %d、單標靶 %d）→ %s/analysis.csv\n", nrow(out), sum(out$dual),
            sum(1 - out$dual), DERIVED_DIR))
