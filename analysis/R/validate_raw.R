# 原始資料檢查（先驗證再分析）。
# 只產生彙總數字：results/data_validation.md（給人看）與 results/data_validation.csv（給程式讀）。
# 不輸出病歷號、生日或任何個別病人資料；不比較兩組的療效。
# 有「錯誤」等級的項目時以非零狀態結束，讓 make 停下來。
source("analysis/R/common.R")

manifest <- verify_manifest()
p <- params()
facts <- study_facts()
dm <- drug_map()

raw <- lapply(setNames(names(p$raw_files), names(p$raw_files)), read_raw, p = p)

checks <- list()
add <- function(id, area, item, n, unit, level, action) {
  checks[[length(checks) + 1]] <<- data.table(
    id = id, area = area, item = item, n = as.integer(n), unit = unit,
    level = if (n > 0) level else "ok", action = if (n > 0) action else "")
}
pts <- function(x) uniqueN(x)

# ── A. 結構 ────────────────────────────────────────────────────────────────
for (k in names(p$expected_columns)) {
  missing <- setdiff(p$expected_columns[[k]], names(raw[[k]]))
  add(sprintf("A1-%s", k), "結構", sprintf("%s 缺少預期欄位", p$raw_files[[k]]),
      length(missing), "欄", "error", paste("缺：", paste(missing, collapse = "、")))
}
if (any(vapply(checks, function(x) x$level == "error", TRUE))) {
  stop("欄位不符，停止檢查：", paste(rbindlist(checks)[level == "error", action], collapse = "；"))
}

# 日期欄位：格式與追蹤截止日
for (k in names(raw)) {
  for (col in grep("date", names(raw[[k]]), value = TRUE)) {
    v <- raw[[k]][[col]]
    d <- as_date(v)
    add(sprintf("A2-%s-%s", k, col), "結構", sprintf("%s 日期格式錯誤或不存在", col),
        sum(v != "" & is.na(d)), "筆", "error", "請資訊室確認原始值")
    add(sprintf("A3-%s-%s", k, col), "結構", sprintf("%s 晚於追蹤截止日（%s）", col, facts$fu_cutoff),
        sum(d > facts$fu_cutoff, na.rm = TRUE), "筆", "error", "請資訊室確認；截止日後的資料不應出現")
  }
}

# 類別欄位允許值
for (k in names(raw)) {
  for (col in intersect(names(p$allowed_values), names(raw[[k]]))) {
    v <- raw[[k]][[col]]
    bad <- v != "" & !v %in% as.character(p$allowed_values[[col]])
    add(sprintf("A4-%s", col), "結構", sprintf("%s 出現未定義的值", col), sum(bad), "筆", "error",
        paste("未定義值：", paste(unique(v[bad]), collapse = "、")))
  }
}

# ── B. 癌登 ────────────────────────────────────────────────────────────────
reg_all <- raw$registry
n_dup <- nrow(reg_all) - pts(reg_all$chart_no)
n_identical <- sum(duplicated(reg_all))
add("B1", "癌登", "同一病人重複登錄，且內容完全相同", n_identical, "筆", "warning",
    "保留一筆即可（程式自動處理）")
add("B2", "癌登", "同一病人重複登錄，且內容不一致", n_dup - n_identical, "筆", "error",
    "請資訊室確認哪一筆正確")
reg <- unique(reg_all)

birth <- as_date(reg$birth_date)
dx <- as_date(reg$dx_date)
age <- as.numeric(dx - birth) / 365.25
add("B3", "癌登", "生日為系統預設值（1900 年或更早）", sum(year(birth) <= 1900, na.rm = TRUE), "人", "error",
    "請資訊室提供正確生日；否則該病人年齡視為缺值")
rng <- p$ranges$age_at_dx
add("B4", "癌登", sprintf("診斷年齡超出 %d–%d 歲", rng[1], rng[2]),
    sum(age < rng[1] | age > rng[2], na.rm = TRUE), "人", "warning", "多半與生日錯誤同源，確認後處理")

ki67 <- reg$ki67
add("B5", "癌登", "Ki-67 寫法不一致（帶 % 符號）", sum(grepl("%", ki67)), "人", "warning",
    "去除 % 後轉為數字（程式自動處理）")
num <- function(x) suppressWarnings(as.numeric(sub("%$", "", trimws(x))))
for (col in c("ER_pct", "PR_pct", "ki67", "BMI", "LVEF_baseline")) {
  v <- reg[[col]]
  x <- num(v)
  r <- p$ranges[[col]]
  add(sprintf("B6-%s", col), "癌登", sprintf("%s 非數字或超出 %s–%s", col, r[1], r[2]),
      sum(v != "" & (is.na(x) | x < r[1] | x > r[2])), "人", "error", "請資訊室確認原始值")
}

# AJCC 第 8 版解剖分期：由 cT/cN/cM 推算，與登錄的分期比對
ajcc8 <- function(t, n, m) {
  tg <- sub("^(T[0-4]|Tis).*$", "\\1", t)
  fifelse(m == "M1", "IV",
  fifelse(n == "N3", "IIIC",
  fifelse(tg == "T4", "IIIB",
  fifelse(n == "N2" | (tg == "T3" & n == "N1"), "IIIA",
  fifelse((tg == "T3" & n == "N0") | (tg == "T2" & n == "N1"), "IIB",
  fifelse((tg == "T2" & n == "N0") | (tg %in% c("T0", "T1") & n == "N1"), "IIA",
  fifelse(tg == "T1" & n == "N0", "IA",
  fifelse(tg == "Tis" & n == "N0", "0", NA_character_))))))))
}
derived_stage <- ajcc8(reg$cT, reg$cN, reg$cM)
add("B7", "癌登", "登錄分期與 cT/cN/cM 推算之 AJCC 第 8 版分期不一致",
    sum(is.na(derived_stage) | derived_stage != reg$stage_ajcc8), "人", "warning",
    "影響收案條件判定；請確認以哪一個為準")

for (col in c("grade", "ki67", "ER_pct", "PR_pct", "HER2_IHC", "menopause", "ECOG", "BMI")) {
  add(sprintf("B8-%s", col), "癌登", sprintf("%s 缺值", col), sum(reg[[col]] == ""), "人", "warning",
      "分析計畫需寫明缺值處理（目前計畫：多重插補）")
}

# 預期中的不符收案條件（分析時依計畫排除，不是資料錯誤）
add("C1", "收案條件", "臨床分期非 II–III 期（0／I 期）", sum(reg$stage_ajcc8 %in% c("0", "IA", "IB")), "人",
    "info", "依計畫排除")
add("C2", "收案條件", "診斷時遠端轉移（cM1／第 IV 期）", sum(reg$cM == "M1" | reg$stage_ajcc8 == "IV"), "人",
    "info", "依計畫排除")
her2_pos <- reg$HER2_IHC == "3+" | reg$HER2_ISH == "Amplified"
add("C3", "收案條件", "HER2 非陽性（IHC 2+ 且 ISH 未擴增或未做，或 IHC 0／1+）", sum(!her2_pos), "人",
    "info", "依計畫排除")
add("C4", "收案條件", "男性病人", sum(reg$sex == "M"), "人", "info",
    "計畫未排除男性；請確認是否納入")

# ── D. 藥囑 ────────────────────────────────────────────────────────────────
ch <- raw$chemo
ch[, order_d := as_date(order_date)]
unmapped <- setdiff(unique(ch$drug_name), dm$raw_name)
add("D1", "藥囑", "藥名不在對照表（analysis/drug_map.csv）", sum(ch$drug_name %in% unmapped), "筆", "error",
    paste("未對照：", paste(unmapped, collapse = "、"), "；請醫師確認後補進對照表"))
mf <- unique(dm[!is.na(market_from), .(drug_name = raw_name, market_from = as.IDate(market_from))])
early <- merge(ch, mf, by = "drug_name")[order_d < market_from]
add("D2", "藥囑", "產品在上市之前就有醫囑", nrow(early), "筆", "error",
    sprintf("涉及 %d 人；產品：%s。疑似資訊室以現行品項代碼回填舊醫囑，請確認藥名是否為當時原始醫囑",
            pts(early$chart_no), paste(unique(early$drug_name), collapse = "、")))
single <- ch[, uniqueN(dose_mg), by = drug_name][, all(V1 == 1)]
add("D3", "藥囑", "劑量欄位每種產品只有單一固定值（看不出依體重或負荷劑量調整）",
    if (single) uniqueN(ch$drug_name) else 0L, "種產品", "warning",
    "劑量欄位疑為標準劑量而非實際給藥量；不用於劑量強度分析，請資訊室說明來源")

first <- ch[, .(first_order = min(order_d), last_order = max(order_d)), by = chart_no]
fu <- raw$followup
fu[, `:=`(last_d = as_date(last_contact_date), rec_d = as_date(recurrence_date), death_d = as_date(death_date))]
x <- merge(ch, fu[, .(chart_no, death_d, last_d)], by = "chart_no")
add("D4", "藥囑", "死亡日期之後仍有醫囑", x[!is.na(death_d) & order_d > death_d, .N], "筆", "error",
    sprintf("涉及 %d 人；死亡日期或醫囑日期有誤，或病歷號對錯人，請資訊室查證",
            x[!is.na(death_d) & order_d > death_d, pts(chart_no)]))
add("D5", "藥囑", "最後一次醫囑晚於「最後追蹤日」", x[order_d > last_d, pts(chart_no)], "人", "warning",
    "最後追蹤日未更新，會低估追蹤時間；分析計畫需決定是否以最後就醫紀錄補正")
fx <- merge(first, reg[, .(chart_no, dx_d = as_date(dx_date))], by = "chart_no")
add("D6", "藥囑", "診斷日期之前就有醫囑", fx[first_order < dx_d, .N], "人", "warning",
    "可能為其他癌症治療或日期錯誤，請確認")
add("D7", "收案條件", sprintf("首次醫囑不在收案期間（%s–%s）", facts$enroll_start, facts$enroll_end),
    fx[first_order < facts$enroll_start | first_order > facts$enroll_end, .N], "人", "info", "依計畫排除")

# ── E. 手術與病理 ──────────────────────────────────────────────────────────
su <- raw$surgery
su[, surg_d := as_date(surgery_date)]
add("E1", "手術病理", "同一病人有多筆手術", nrow(su) - pts(su$chart_no), "筆", "warning",
    "需決定以哪一次手術判定 pCR")
add("E2", "手術病理", "有手術但術後病理 ypT 或 ypN 空白", su[ypT == "" | ypN == "", .N], "人", "warning",
    "無法判定 pCR；請調閱病理報告補登，否則依計畫處理")
add("E3", "手術病理", "術後病理為 ypN0(i+)（淋巴結僅孤立腫瘤細胞）", su[ypN == "ypN0(i+)", .N], "人", "warning",
    "需醫師決定：pCR 定義（ypT0/is ypN0）是否將 ypN0(i+) 視為 pCR，寫進分析計畫")
sx <- merge(su, reg[, .(chart_no, dx_d = as_date(dx_date))], by = "chart_no")
add("E4", "手術病理", "手術日期早於診斷日期", sx[surg_d < dx_d, .N], "人", "error", "請資訊室查證日期")
sx <- merge(su, first, by = "chart_no", all.x = TRUE)
add("E5", "手術病理", "手術早於第一次醫囑（先開刀、非術前治療）", sx[!is.na(first_order) & surg_d < first_order, .N],
    "人", "warning", "屬先手術者依計畫排除；若是日期錯誤請查證")
add("E6", "收案條件", "有手術但本院無任何抗癌藥醫囑", sx[is.na(first_order), .N], "人", "info",
    "未在本院接受術前治療，依計畫排除")

# ── F. 追蹤 ────────────────────────────────────────────────────────────────
add("F1", "追蹤", "存活狀態與死亡日期不一致",
    fu[(vital_status == "Dead") != !is.na(death_d), .N], "人", "error", "請資訊室查證")
add("F2", "追蹤", "復發類型與復發日期只填一個", fu[(recurrence_type == "") != is.na(rec_d), .N], "人", "error",
    "請資訊室查證")
fx <- merge(fu, reg[, .(chart_no, dx_d = as_date(dx_date))], by = "chart_no")
add("F3", "追蹤", "復發、死亡或最後追蹤日早於診斷日",
    fx[rec_d < dx_d | death_d < dx_d | last_d < dx_d, .N], "人", "error", "請資訊室查證")
add("F4", "追蹤", "復發日期晚於死亡日期", fu[rec_d > death_d, .N], "人", "error", "請資訊室查證")
add("F5", "追蹤", "復發或死亡晚於最後追蹤日", fu[rec_d > last_d | death_d > last_d, .N], "人", "error",
    "最後追蹤日應不早於任何事件，請資訊室查證")
fx <- merge(fu, su[, .(chart_no, surg_d)], by = "chart_no", all.x = TRUE)
add("F6", "追蹤", "術後復發（局部／區域／遠端）的日期不晚於手術日",
    fx[recurrence_type %in% c("Local", "Regional", "Distant") & rec_d <= surg_d, .N], "人", "error",
    "術後復發不可能早於手術；請查證是否應為「術前惡化」或日期錯誤")

# ── G. 檔案之間的對應 ──────────────────────────────────────────────────────
for (k in c("chemo", "surgery", "followup")) {
  add(sprintf("G1-%s", k), "對應", sprintf("%s 的病歷號不在癌登", p$raw_files[[k]]),
      pts(raw[[k]][!chart_no %in% reg$chart_no, chart_no]), "人", "error", "請資訊室確認")
}
add("G2", "對應", "癌登病人沒有追蹤資料", sum(!reg$chart_no %in% fu$chart_no), "人", "error",
    "請資訊室補齊")
add("G3", "收案條件", "癌登病人在本院無任何抗癌藥醫囑", sum(!reg$chart_no %in% ch$chart_no), "人", "info",
    "未在本院接受術前治療，依計畫排除")
no_surg <- merge(reg[!chart_no %in% su$chart_no, .(chart_no)], fu[, .(chart_no, recurrence_type)], by = "chart_no")
no_surg[, treated := chart_no %in% ch$chart_no]
add("G4", "對應", "有本院醫囑、沒有手術紀錄、也沒有「術前惡化」",
    no_surg[treated & recurrence_type != "Progression before surgery", .N], "人", "warning",
    "可能在他院手術（依計畫排除）或尚未手術；請資訊室／病歷確認，影響 pCR 分母")

# ── 輸出 ───────────────────────────────────────────────────────────────────
res <- rbindlist(checks)
res[, level := factor(level, c("error", "warning", "info", "ok"))]
setorder(res, level, id)
dir.create(RESULTS_DIR, showWarnings = FALSE)
fwrite(res, file.path(RESULTS_DIR, "data_validation.csv"))

usage <- merge(ch, dm[, .(drug_name = raw_name, agent)], by = "drug_name", allow.cartesian = TRUE)[
  , .(first = min(order_d), last = max(order_d), patients = pts(chart_no)), by = .(agent, drug_name)][order(agent, first)]

prov <- provenance(manifest)
label <- c(error = "錯誤", warning = "注意", info = "資訊", ok = "通過")
md <- c(
  "# 原始資料檢查報告",
  "",
  "> ⚠️ Synthetic data for teaching — 教學示範用模擬資料。",
  "> 本報告只含彙總數字，不含病歷號、生日或任何個別病人資料；也未比較兩組療效。",
  "",
  sprintf("- IRB 編號：%s", facts$irb_no),
  sprintf("- 收案期間：%s 至 %s；追蹤截止：%s（讀自 config.toml）", facts$enroll_start, facts$enroll_end, facts$fu_cutoff),
  sprintf("- 產生時間：%s", prov$generated),
  sprintf("- 程式版本（git）：%s", prov$git_commit),
  sprintf("- 軟體：%s；%s", prov$r_version, prov$packages),
  "- 原始資料 checksum：與 `data/raw/MANIFEST.sha256` 全部相符",
  "",
  "| 檔案 | 列數 | 病人數 | SHA-256（前 12 碼） |",
  "|---|---:|---:|---|",
  vapply(names(raw), function(k) sprintf("| %s | %d | %d | `%s` |", p$raw_files[[k]], nrow(raw[[k]]),
         pts(raw[[k]]$chart_no), substr(manifest[file == p$raw_files[[k]], sha256], 1, 12)), ""),
  "",
  "## 總結",
  "",
  sprintf("- **錯誤 %d 項**：資料本身可能有誤，需資訊室查證；查清楚之前不進入分析。", res[level == "error", .N]),
  sprintf("- **注意 %d 項**：資料可用，但需決定處理方式並寫進分析計畫。", res[level == "warning", .N]),
  sprintf("- **資訊 %d 項**：預期中的不符收案條件，分析時依計畫排除。", res[level == "info", .N]),
  sprintf("- **通過 %d 項**。", res[level == "ok", .N]),
  ""
)
for (lv in c("error", "warning", "info")) {
  r <- res[level == lv]
  if (!nrow(r)) next
  md <- c(md, sprintf("## %s", label[[lv]]), "", "| 編號 | 範圍 | 檢查項目 | 數量 | 建議處理 |", "|---|---|---|---:|---|",
          r[, sprintf("| %s | %s | %s | %d %s | %s |", id, area, item, n, unit, action)], "")
}
md <- c(md, "## 通過的檢查", "", paste0("- ", res[level == "ok", sprintf("%s 無「%s」", id, item)]), "",
        "## 各藥品醫囑期間（供判斷資料合理性）", "",
        "| 藥物 | 藥囑名稱 | 最早 | 最晚 | 病人數 |", "|---|---|---|---|---:|",
        usage[, sprintf("| %s | %s | %s | %s | %d |", agent, drug_name, first, last, patients)], "",
        "---", "", "由 `make data-check`（analysis/R/validate_raw.R）產生，請勿手改。")
writeLines(md, file.path(RESULTS_DIR, "data_validation.md"))

n_err <- res[level == "error", .N]
cat(sprintf("資料檢查：錯誤 %d、注意 %d、資訊 %d、通過 %d → %s\n", n_err, res[level == "warning", .N],
            res[level == "info", .N], res[level == "ok", .N], file.path(RESULTS_DIR, "data_validation.md")))
if (n_err > 0) quit(status = 1)
