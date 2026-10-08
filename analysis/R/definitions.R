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

# 病理報告的百分比欄位（如 Ki-67 寫成 "64%" 或 "64"）→ 數字；空白為 NA
parse_pct <- function(x) suppressWarnings(as.numeric(sub("%$", "", trimws(x))))

# ER／PR 陽性：染色百分比 ≥ cutoff（params$receptor_positive_cutoff）
receptor_positive <- function(pct, cutoff) parse_pct(pct) >= cutoff

# 術前化療組合（依優先順序）：含 anthracycline → 含 carboplatin（無 anthracycline）→ 只有 taxane
chemo_backbone <- function(neo_anthracycline, neo_platinum, neo_taxane) {
  fcase(neo_anthracycline, "Anthracycline-based",
        neo_platinum, "Carboplatin-based",
        neo_taxane, "Taxane only",
        default = "Other")
}

# 死亡日之後的醫囑為預開未執行（資訊室查證 D4），不視為給藥。orders 需有 study_id, order_d。
drop_unexecuted_orders <- function(orders, followup) {
  x <- merge(orders, followup[, .(study_id, death_d)], by = "study_id", all.x = TRUE)
  x[is.na(death_d) | order_d <= death_d][, death_d := NULL][]
}

# 追蹤終點（資訊室查證 D5）：最後一次就醫 = 最後門診與最後一次醫囑取較晚者；
# 死亡者為死亡日；不超過追蹤截止日
followup_end <- function(last_contact_d, last_order_d, death_d, cutoff) {
  end <- pmax(last_contact_d, last_order_d, na.rm = TRUE)
  end <- fifelse(!is.na(death_d), death_d, end)
  pmin(end, cutoff, na.rm = TRUE)
}

# pCR = ypT0/is ypN0：乳房無侵襲性癌殘留（原位癌可）且淋巴結完全無腫瘤細胞。
# ypN0(i+)（孤立腫瘤細胞）與 ypN1mi 都不是 pCR（決定紀錄：analysis/decision_log.md 2026-10-09；
# Provenzano 2015 doi:10.1038/modpathol.2015.74、Bossuyt 2015 doi:10.1093/annonc/mdv161、
# ICCR 2024 doi:10.1111/his.15165）。未手術（術前惡化）視為非 pCR；有手術但 yp 分期空白為 NA。
PCR_YPT <- c("ypT0", "ypTis")
PCR_YPN <- "ypN0"
pcr <- function(ypT, ypN, had_surgery) {
  fifelse(!had_surgery, FALSE,
          fifelse(is.na(ypT) | is.na(ypN) | ypT == "" | ypN == "", NA, ypT %in% PCR_YPT & ypN %in% PCR_YPN))
}

# 術前治療摘要（每位有醫囑的病人一列）
#   index_d          指標日 = 第一筆抗癌藥醫囑日
#   upfront_surgery  手術早於指標日（先開刀）
#   window_end       術前治療期間的最後一天：手術前一天；沒有手術但術前惡化者為惡化日；兩者皆無則為 NA
#   neo_*            術前治療期間 [index_d, window_end] 內是否用過該類藥
#   chemo_backbone   術前化療組合（見 chemo_backbone()）
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
                 neo_chemo = any(agent_class %in% CHEMO_CLASSES),
                 neo_anthracycline = any(agent_class == "anthracycline"),
                 neo_platinum = any(agent_class == "platinum"),
                 neo_taxane = any(agent_class == "taxane")), by = study_id]
  s <- merge(s, flags, by = "study_id", all.x = TRUE)
  for (col in grep("^neo_", names(s), value = TRUE)) {
    set(s, which(is.na(s[[col]])), col, FALSE)
  }
  s[, chemo_backbone := chemo_backbone(neo_anthracycline, neo_platinum, neo_taxane)]
  s[, treatment_group := fcase(neo_trastuzumab & neo_pertuzumab, "dual",
                               neo_trastuzumab & !neo_pertuzumab, "single",
                               default = NA_character_)]
  s[]
}
