# 共用定義：每個定義只寫在這裡，收案流程與之後的分析都 source 這個檔案。
# 對應測試：analysis/tests/test_definitions.R
suppressPackageStartupMessages(library(data.table))

CHEMO_CLASSES <- c("taxane", "platinum", "anthracycline", "alkylating")

# 藥囑 → 每筆醫囑 × 成分一列（Phesgo 同時含 pertuzumab 與 trastuzumab）。只做完全比對。
map_orders <- function(orders, dm) {
  unmapped <- setdiff(unique(orders$drug_name), dm$raw_name)
  if (length(unmapped)) stop("藥名不在 analysis/drug_map.csv：", paste(unmapped, collapse = "、"))
  merge(orders, dm[, .(drug_name = raw_name, agent, agent_class)], by = "drug_name", allow.cartesian = TRUE)
}

# HER2 陽性：IHC 3+，或 ISH 擴增
her2_positive <- function(ihc, ish) ihc == "3+" | ish == "Amplified"

# 術前治療摘要（每位有醫囑的病人一列）
#   index_d          指標日 = 第一筆抗癌藥醫囑日
#   upfront_surgery  手術早於指標日（先開刀）
#   window_end       術前治療期間的最後一天：手術前一天；沒有手術但術前惡化者為惡化日；兩者皆無則為 NA
#   neo_*            術前治療期間 [index_d, window_end] 內是否用過該類藥
#   treatment_group  dual = trastuzumab + pertuzumab；single = trastuzumab 未合併 pertuzumab；其他為 NA
# orders_mapped: study_id, order_d, agent, agent_class；surgery: study_id, surg_d；
# followup: study_id, recurrence_type, rec_d
neoadjuvant_summary <- function(orders_mapped, surgery, followup) {
  idx <- orders_mapped[, .(index_d = min(order_d)), by = study_id]
  surg <- surgery[, .(surg_d = min(surg_d)), by = study_id]
  pbs <- followup[recurrence_type == "Progression before surgery", .(study_id, pbs_d = rec_d)]
  s <- merge(merge(idx, surg, by = "study_id", all.x = TRUE), pbs, by = "study_id", all.x = TRUE)
  s[, upfront_surgery := !is.na(surg_d) & surg_d < index_d]
  s[, window_end := fifelse(!is.na(surg_d), surg_d - 1L, pbs_d)]

  w <- merge(orders_mapped, s[, .(study_id, index_d, window_end)], by = "study_id")[
    !is.na(window_end) & order_d >= index_d & order_d <= window_end]
  flags <- w[, .(neo_trastuzumab = any(agent == "trastuzumab"),
                 neo_pertuzumab = any(agent == "pertuzumab"),
                 neo_tdm1 = any(agent == "trastuzumab_emtansine"),
                 neo_chemo = any(agent_class %in% CHEMO_CLASSES)), by = study_id]
  s <- merge(s, flags, by = "study_id", all.x = TRUE)
  for (col in c("neo_trastuzumab", "neo_pertuzumab", "neo_tdm1", "neo_chemo")) {
    set(s, which(is.na(s[[col]])), col, FALSE)
  }
  s[, treatment_group := fcase(neo_trastuzumab & neo_pertuzumab, "dual",
                               neo_trastuzumab & !neo_pertuzumab, "single",
                               default = NA_character_)]
  s[]
}
