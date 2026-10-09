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

## 2026-10-09　統計分析計畫 v1.0 草案：與 IRB 核准計畫書的差異

計畫書指 IRB 核准的 `中文計畫摘要.md`（tag `irb-approved`）。以下差異都是在看任何療效結果之前決定的。

| # | 計畫書 | SAP v1.0 | 理由 |
|---|---|---|---|
| 1 | 主分析用 IPTW | **重疊加權**（ATO）；IPTW 不採用 | 兩組治療年代幾乎不重疊。設計階段試算（只用基期資料）顯示 IPTW 下單標靶組的有效樣本數僅約 5 人，且加權後仍不平衡；重疊加權可讓所有共變項完全平衡 |
| 2 | 傾向分數共變項：年齡、T/N、荷爾蒙受體、分級、化療方案、年份 | 另外加入停經狀態、ECOG、BMI、LVEF、HER2 判定方式、Ki-67 | 都是治療前特徵，可能影響治療選擇；涵蓋原列的所有變項 |
| 3 | EFS 依術後是否使用 T-DM1 分層 | 只做描述性報告 | 術後 T-DM1 取決於術前治療反應，屬治療後變項，分層會造成偏差 |
| 4 | EFS 事件含對側侵襲性乳癌、第二原發癌 | 不含 | 資料中沒有這兩個欄位；列為研究限制 |
| 5 | 樣本數段落：檢定力逾 95% | 依有效樣本數估計，約 60% | 重疊加權後的有效樣本數遠小於全部人數；結果以效應值與信賴區間為主 |
| 6 | （無） | 新增敏感度分析：pCR 改用 ypT0 ypN0、傳統多變項迴歸、完整個案分析；新增探索性次族群（荷爾蒙受體） | 增加結果的可信度 |

是否需要向 IRB 提出修正案：待計畫主持人決定。

## 2026-12-07　IRB 核准第 1 次修正案

上一節列出的 6 項差異，連同資料收集項目增列 BMI、LVEF，已以第 1 次修正案送審（tag `irb-amendment-1`）並獲同意修正
（`correspondence/IRB修正案1_核准通知.md`）。統計分析計畫 v1.0 與 IRB 核准之計畫書自此一致。

## 2026-10-09　期刊第一輪審查（Major Revision）：事後分析

審查意見：`correspondence/JCRP_decision_round1.md`。以下分析**不在 SAP v1.0 內**，為回應審稿人而做，論文中一律標明
post hoc，與事先訂定的分析分開報告；方法與主分析相同（同一份多重插補與重疊加權；`analysis/R/posthoc_revision1.R`）。

| 審稿意見 | 事後分析 |
|---|---|
| R1.1 年代與治療重疊 | 兩組傾向分數分布（補充圖 S2）、共同支持區比例、各年代占的權重；傾向分數中年份改用自然樣條（3 df） |
| R1.2 術後 T-DM1 | **不依術後 T-DM1 分層**（術後 T-DM1 取決於術前治療反應，屬治療後變項，分層會造成偏差；理由同 2026-10-09 SAP 差異 #3）。改為只納入 2012–2019 年開始治療者（術後 T-DM1 尚未使用）比較 EFS |
| R1.3 無病理結果者 | 排除術前惡化者；將他院手術而排除者（依指標日起 180 天內有無 pertuzumab 歸組）分別假設全部 pCR 與全部非 pCR（極端情境） |
| R2.1 時間零點 | 描述 pertuzumab 加入的時間，以及單標靶組最早手術或惡化的時間（檢查是否可能有不死時間偏差） |
| R2.2 追蹤時間不等 | 追蹤截在 5 年的加權 Cox 模型；報告 SAP 已計算的 5 年 RMST 差 |

- **R1.2 做法的決定者**：計畫主持人指示「逐點修改」，未另行指定；採分析者建議的做法（不分層、改做 2012–2019 限縮分析），並在回覆信中說明理由。
- **需誠實報告的結果**：他院手術者全部假設為 pCR 時，OR 降為 1.40 且信賴區間跨 1；此為極端情境，論文與回覆信照實呈現。
