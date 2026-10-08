# 分析決定紀錄

每一項影響分析的決定：日期、決定者、內容、理由、依據。統計分析計畫（SAP）定稿後，
任何修改也記在這裡並註明理由。

> 教學示範：人員與資料皆為虛構（synthetic data for teaching）。

## 2026-10-09　pCR 定義：ypN0(i+) 不算 pCR

- **決定者**：計畫主持人
- **決定**：pCR 採國際通用定義 ypT0/is ypN0。淋巴結僅有孤立腫瘤細胞（ypN0(i+)）或微轉移（ypN1mi）
  都**不算** pCR；乳房只剩原位癌（ypTis）算 pCR。未手術者（術前惡化）為非 pCR。
- **理由**：孤立腫瘤細胞仍是殘留的癌細胞，且與較差的預後相關；國際共識明確排除於 pCR 之外。
  與 IRB 核准計畫「術後乳房及腋下淋巴結無侵襲性癌殘留」一致，不需修正案。
- **影響**：收案名單中 27 位為 ypN0(i+)，歸為非 pCR。
- **依據**（OpenEvidence 查詢，DOI 經 Crossref 驗證）：
  - Provenzano E, et al. Standardization of pathologic evaluation and reporting of postneoadjuvant
    specimens in clinical trials of breast cancer: recommendations from an international working group.
    *Mod Pathol*. 2015;28(9):1185-1201. doi:10.1038/modpathol.2015.74
  - Bossuyt V, et al. Recommendations for standardized pathological characterization of residual disease
    for neoadjuvant clinical trials of breast cancer by the BIG-NABCG collaboration. *Ann Oncol*.
    2015;26(7):1280-1291. doi:10.1093/annonc/mdv161
  - Bossuyt V, et al. A dedicated structured data set for reporting of invasive carcinoma of the breast in
    the setting of neoadjuvant therapy: recommendations from the International Collaboration on Cancer
    Reporting (ICCR). *Histopathology*. 2024;84(7):1111-1129. doi:10.1111/his.15165
- **程式**：`analysis/R/definitions.R` 的 `pcr()`；測試 `analysis/tests/test_definitions.R`

## 2026-10-09　資訊室查證後的資料處理

依資訊室回覆（`correspondence/資訊室_查詢回覆.md`），逐項處理記於 `analysis/data_queries.yaml`。
影響分析定義的兩項：

- **死亡後的醫囑**為預開未執行，不視為給藥（`drop_unexecuted_orders()`）。
- **追蹤終點**取最後一次就醫（最後門診與最後一次醫囑取較晚者），死亡者取死亡日，不超過追蹤截止日
  （`followup_end()`）。限制：存活者若有預開未執行的醫囑，追蹤時間可能略為高估。
