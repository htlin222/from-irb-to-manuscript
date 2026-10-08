# 原始資料檢查報告

> ⚠️ Synthetic data for teaching — 教學示範用模擬資料。
> 本報告只含彙總數字，不含病歷號、生日或任何個別病人資料；也未比較兩組療效。

- IRB 編號：DEMO-2026-0412
- 收案期間：2012-01-01 至 2023-12-31；追蹤截止：2025-12-31（讀自 config.toml）
- 產生時間：2026-10-09 07:49:25 CST
- 程式版本（git）：b5f155a
- 軟體：R version 4.5.1 (2025-06-13)；data.table 1.17.8、yaml 2.3.10、RcppTOML 0.2.3、digest 0.6.37、jsonlite 2.0.0
- 原始資料 checksum：與 `data/raw/MANIFEST.sha256` 全部相符

| 檔案 | 列數 | 病人數 | SHA-256（前 12 碼） |
|---|---:|---:|---|
| registry_breast_her2.csv | 703 | 700 | `bf434011c39f` |
| chemo_orders.csv | 23105 | 670 | `f95dce8d6f78` |
| surgery_pathology.csv | 649 | 649 | `c85ee1671adb` |
| followup.csv | 700 | 700 | `fd88e1cda5cc` |

## 總結

- **錯誤 5 項**：資料本身可能有誤，需資訊室查證；查清楚之前不進入分析。
- **注意 11 項**：資料可用，但需決定處理方式並寫進分析計畫。
- **資訊 6 項**：預期中的不符收案條件，分析時依計畫排除。
- **通過 59 項**。

## 錯誤

| 編號 | 範圍 | 檢查項目 | 數量 | 建議處理 |
|---|---|---|---:|---|
| B3 | 癌登 | 生日為系統預設值（1900 年或更早） | 1 人 | 請資訊室提供正確生日；否則該病人年齡視為缺值 |
| D2 | 藥囑 | 產品在上市之前就有醫囑 | 767 筆 | 涉及 195 人；產品：Herzuma 150mg、trastuzumab (Ontruzant)。疑似資訊室以現行品項代碼回填舊醫囑，請確認藥名是否為當時原始醫囑 |
| D4 | 藥囑 | 死亡日期之後仍有醫囑 | 32 筆 | 涉及 4 人；死亡日期或醫囑日期有誤，或病歷號對錯人，請資訊室查證 |
| E4 | 手術病理 | 手術日期早於診斷日期 | 2 人 | 請資訊室查證日期 |
| F6 | 追蹤 | 術後復發（局部／區域／遠端）的日期不晚於手術日 | 2 人 | 術後復發不可能早於手術；請查證是否應為「術前惡化」或日期錯誤 |

## 注意

| 編號 | 範圍 | 檢查項目 | 數量 | 建議處理 |
|---|---|---|---:|---|
| B1 | 癌登 | 同一病人重複登錄，且內容完全相同 | 3 筆 | 保留一筆即可（程式自動處理） |
| B4 | 癌登 | 診斷年齡超出 18–100 歲 | 1 人 | 多半與生日錯誤同源，確認後處理 |
| B5 | 癌登 | Ki-67 寫法不一致（帶 % 符號） | 21 人 | 去除 % 後轉為數字（程式自動處理） |
| B8-grade | 癌登 | grade 缺值 | 54 人 | 分析計畫需寫明缺值處理（目前計畫：多重插補） |
| B8-ki67 | 癌登 | ki67 缺值 | 82 人 | 分析計畫需寫明缺值處理（目前計畫：多重插補） |
| D3 | 藥囑 | 劑量欄位每種產品只有單一固定值（看不出依體重或負荷劑量調整） | 24 種產品 | 劑量欄位疑為標準劑量而非實際給藥量；不用於劑量強度分析，請資訊室說明來源 |
| D5 | 藥囑 | 最後一次醫囑晚於「最後追蹤日」 | 23 人 | 最後追蹤日未更新，會低估追蹤時間；分析計畫需決定是否以最後就醫紀錄補正 |
| E2 | 手術病理 | 有手術但術後病理 ypT 或 ypN 空白 | 18 人 | 無法判定 pCR；請調閱病理報告補登，否則依計畫處理 |
| E3 | 手術病理 | 術後病理為 ypN0(i+)（淋巴結僅孤立腫瘤細胞） | 27 人 | 需醫師決定：pCR 定義（ypT0/is ypN0）是否將 ypN0(i+) 視為 pCR，寫進分析計畫 |
| E5 | 手術病理 | 手術早於第一次醫囑（先開刀、非術前治療） | 2 人 | 屬先手術者依計畫排除；若是日期錯誤請查證 |
| G4 | 對應 | 有本院醫囑、沒有手術紀錄、也沒有「術前惡化」 | 30 人 | 可能在他院手術（依計畫排除）或尚未手術；請資訊室／病歷確認，影響 pCR 分母 |

## 資訊

| 編號 | 範圍 | 檢查項目 | 數量 | 建議處理 |
|---|---|---|---:|---|
| C1 | 收案條件 | 臨床分期非 II–III 期（0／I 期） | 27 人 | 依計畫排除 |
| C2 | 收案條件 | 診斷時遠端轉移（cM1／第 IV 期） | 14 人 | 依計畫排除 |
| C3 | 收案條件 | HER2 非陽性（IHC 2+ 且 ISH 未擴增或未做，或 IHC 0／1+） | 11 人 | 依計畫排除 |
| C4 | 收案條件 | 男性病人 | 1 人 | 計畫未排除男性；請確認是否納入 |
| E6 | 收案條件 | 有手術但本院無任何抗癌藥醫囑 | 18 人 | 未在本院接受術前治療，依計畫排除 |
| G3 | 收案條件 | 癌登病人在本院無任何抗癌藥醫囑 | 30 人 | 未在本院接受術前治療，依計畫排除 |

## 通過的檢查

- A1-chemo 無「chemo_orders.csv 缺少預期欄位」
- A1-followup 無「followup.csv 缺少預期欄位」
- A1-registry 無「registry_breast_her2.csv 缺少預期欄位」
- A1-surgery 無「surgery_pathology.csv 缺少預期欄位」
- A2-chemo-order_date 無「order_date 日期格式錯誤或不存在」
- A2-followup-death_date 無「death_date 日期格式錯誤或不存在」
- A2-followup-last_contact_date 無「last_contact_date 日期格式錯誤或不存在」
- A2-followup-recurrence_date 無「recurrence_date 日期格式錯誤或不存在」
- A2-registry-birth_date 無「birth_date 日期格式錯誤或不存在」
- A2-registry-dx_date 無「dx_date 日期格式錯誤或不存在」
- A2-surgery-surgery_date 無「surgery_date 日期格式錯誤或不存在」
- A3-chemo-order_date 無「order_date 晚於追蹤截止日（2025-12-31）」
- A3-followup-death_date 無「death_date 晚於追蹤截止日（2025-12-31）」
- A3-followup-last_contact_date 無「last_contact_date 晚於追蹤截止日（2025-12-31）」
- A3-followup-recurrence_date 無「recurrence_date 晚於追蹤截止日（2025-12-31）」
- A3-registry-birth_date 無「birth_date 晚於追蹤截止日（2025-12-31）」
- A3-registry-dx_date 無「dx_date 晚於追蹤截止日（2025-12-31）」
- A3-surgery-surgery_date 無「surgery_date 晚於追蹤截止日（2025-12-31）」
- A4-ECOG 無「ECOG 出現未定義的值」
- A4-HER2_IHC 無「HER2_IHC 出現未定義的值」
- A4-HER2_ISH 無「HER2_ISH 出現未定義的值」
- A4-cM 無「cM 出現未定義的值」
- A4-cN 無「cN 出現未定義的值」
- A4-cT 無「cT 出現未定義的值」
- A4-grade 無「grade 出現未定義的值」
- A4-menopause 無「menopause 出現未定義的值」
- A4-recurrence_type 無「recurrence_type 出現未定義的值」
- A4-sex 無「sex 出現未定義的值」
- A4-stage_ajcc8 無「stage_ajcc8 出現未定義的值」
- A4-surgery_type 無「surgery_type 出現未定義的值」
- A4-vital_status 無「vital_status 出現未定義的值」
- A4-ypN 無「ypN 出現未定義的值」
- A4-ypT 無「ypT 出現未定義的值」
- B2 無「同一病人重複登錄，且內容不一致」
- B6-BMI 無「BMI 非數字或超出 12–60」
- B6-ER_pct 無「ER_pct 非數字或超出 0–100」
- B6-LVEF_baseline 無「LVEF_baseline 非數字或超出 20–90」
- B6-PR_pct 無「PR_pct 非數字或超出 0–100」
- B6-ki67 無「ki67 非數字或超出 0–100」
- B7 無「登錄分期與 cT/cN/cM 推算之 AJCC 第 8 版分期不一致」
- B8-BMI 無「BMI 缺值」
- B8-ECOG 無「ECOG 缺值」
- B8-ER_pct 無「ER_pct 缺值」
- B8-HER2_IHC 無「HER2_IHC 缺值」
- B8-PR_pct 無「PR_pct 缺值」
- B8-menopause 無「menopause 缺值」
- D1 無「藥名不在對照表（analysis/drug_map.csv）」
- D6 無「診斷日期之前就有醫囑」
- D7 無「首次醫囑不在收案期間（2012-01-01–2023-12-31）」
- E1 無「同一病人有多筆手術」
- F1 無「存活狀態與死亡日期不一致」
- F2 無「復發類型與復發日期只填一個」
- F3 無「復發、死亡或最後追蹤日早於診斷日」
- F4 無「復發日期晚於死亡日期」
- F5 無「復發或死亡晚於最後追蹤日」
- G1-chemo 無「chemo_orders.csv 的病歷號不在癌登」
- G1-followup 無「followup.csv 的病歷號不在癌登」
- G1-surgery 無「surgery_pathology.csv 的病歷號不在癌登」
- G2 無「癌登病人沒有追蹤資料」

## 各藥品醫囑期間（供判斷資料合理性）

| 藥物 | 藥囑名稱 | 最早 | 最晚 | 病人數 |
|---|---|---|---|---:|
| carboplatin | Carboplatin | 2012-05-03 | 2024-04-07 | 416 |
| carboplatin | Paraplatin | 2012-05-13 | 2024-03-17 | 417 |
| cyclophosphamide | Endoxan | 2012-02-06 | 2024-01-25 | 234 |
| cyclophosphamide | Cyclophosphamide | 2012-02-27 | 2024-02-09 | 232 |
| docetaxel | DOCETAXEL 80MG | 2012-04-30 | 2024-04-07 | 531 |
| docetaxel | Docetaxel | 2012-05-24 | 2024-05-03 | 535 |
| docetaxel | Taxotere | 2012-06-03 | 2024-04-12 | 536 |
| epirubicin | Pharmorubicin | 2012-02-06 | 2024-01-25 | 230 |
| epirubicin | Epirubicin | 2012-04-09 | 2024-02-09 | 235 |
| paclitaxel | Taxol | 2012-05-21 | 2024-03-24 | 100 |
| paclitaxel | Genexol | 2012-06-11 | 2024-04-18 | 91 |
| paclitaxel | Paclitaxel | 2012-11-25 | 2024-01-12 | 102 |
| pertuzumab | Perjeta | 2013-04-05 | 2024-05-03 | 383 |
| pertuzumab | PERJETA 420MG/14ML | 2013-04-26 | 2024-04-18 | 391 |
| pertuzumab | Pertuzumab | 2013-06-28 | 2024-03-24 | 382 |
| pertuzumab | Phesgo 1200/600 SC | 2021-06-27 | 2024-04-12 | 148 |
| trastuzumab | Herceptin | 2012-04-30 | 2025-03-08 | 579 |
| trastuzumab | Herzuma 150mg | 2012-05-03 | 2025-02-17 | 585 |
| trastuzumab | HERCEPTIN 440MG INJ | 2012-05-13 | 2025-02-19 | 595 |
| trastuzumab | trastuzumab (Ontruzant) | 2012-06-14 | 2024-12-21 | 584 |
| trastuzumab | Trastuzumab | 2012-07-05 | 2025-02-01 | 558 |
| trastuzumab | Phesgo 1200/600 SC | 2021-06-27 | 2024-04-12 | 148 |
| trastuzumab_emtansine | T-DM1 (Kadcyla) 160mg | 2020-07-20 | 2025-03-01 | 143 |
| trastuzumab_emtansine | Trastuzumab emtansine | 2020-08-10 | 2025-03-23 | 143 |
| trastuzumab_emtansine | Kadcyla | 2020-09-16 | 2025-04-12 | 143 |

---

由 `make data-check`（analysis/R/validate_raw.R）產生，請勿手改。
