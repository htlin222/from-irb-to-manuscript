# 從 IRB 到投稿：一個回溯性研究的完整旅程

**🎬 看錄影：<https://htlin222.github.io/from-irb-to-manuscript/>**　·　📝 [全部 prompt](PROMPTS.md)　·　🎯 [AI 估得對嗎？](demo/TRUTH.md)

一位醫師想知道：**早期 HER2 陽性乳癌，術前用「雙標靶」（trastuzumab + pertuzumab）是不是比「單標靶」好？**
看的是手術時腫瘤完全消失的比例（pCR）、無事件存活（EFS）與整體存活（OS）。

這個 repo 是那段旅程的**完整紀錄**：一段沒有剪接的 Claude Code 對話，34 句很短、不用術語的話，
從 IRB 新案送審一路做到期刊接受與 IRB 結案。每一步的產物都在這裡，每個里程碑都有 git 標籤。

> ⚠️ **教學示範。** 所有病人、人名、單位、IRB 編號與期刊往來信件都是**虛構／模擬**的。
> `manuscript/` 與 `submission/` 裡的論文示範稿**由 AI 撰寫**；JCRP 等期刊規定生成式 AI 不得撰寫論文或其主要部分，
> **真實投稿時，內文必須由作者親自撰寫。**（這一點是錄影中 AI 自己查到、停下來提醒的——見第 25 章。）

## 給新手：prompt 長什麼樣子

全部都是一句話。統計方法不是醫師指定的，而是先問「有哪些方法」再選：

```
14. 兩組病人本來就不一樣。要公平比較，有哪些方法？用白話說明，並推薦一個。
15. 就照你的推薦。先寫分析計畫，給我看重點。
16. 開始分析：pCR、EFS、OS 都要。
```

外面寄來的東西（IRB 審查意見、資訊室的資料、期刊審稿意見）放進 `inbox/`，prompt 只說「在 inbox」。完整清單：[PROMPTS.md](PROMPTS.md)。

## 旅程與里程碑

| 階段 | 章節 | git 標籤 | 主要產物 |
|---|---|---|---|
| 開始之前 | 01–02 | | 題目可行性、最大困難（年代差異） |
| IRB 初審 | 03–05 | `irb-initial-review` | SF001/002/003/005/094、中文計畫摘要（`output/`，PDF） |
| IRB 複審 | 06–08 | `irb-re-review`、`irb-approved` | 審查意見回覆表、SF019 — [`correspondence/`](correspondence/) |
| 拿到資料 | 09–13 | | 原始資料唯讀＋checksum、資料檢查報告、收案流程圖、Table 1、資訊室更正 |
| 公平比較 | 14–20 | `sap-v1.0`、`analysis-complete` | 分析計畫（看結果前鎖定）、重疊加權、敏感度分析、E-value |
| IRB 修正案 | 21–22 | `irb-amendment-1`、`irb-amendment-1-approved` | SF014/015/016（分析方法與原計畫不同，送修正案） |
| 寫論文 | 23–28 | `jcrp-submission-v1` | 期刊規定檔、查證過的文獻、Quarto 原稿、投稿包（title page / blinded article / JPEG 圖 / STROBE / cover letter） |
| 審稿來回 | 29–33 | `jcrp-revision-1`、`jcrp-revision-2`、`jcrp-accepted` | 逐點回覆信、標示修改處的修訂稿、事後分析（標明 post hoc）、IRB 結案文件 |
| 回顧 | 34 | | 哪些是 AI 判斷、哪些是固定程式、醫師一定要親自檢查什麼 |

想看某一刻的樣子：`git checkout irb-initial-review`（或任何標籤）。

## 結果（模擬資料）

615 位病人：雙標靶 416、單標靶 199。兩種治療用在不同年代，所以**不調整時幾乎看不出差別**（pCR 46.9% vs 45.2%）；
以重疊加權（overlap weighting）平衡年代與臨床特徵後，pCR 勝算比 2.01（95% CI 1.12–3.62）。
EFS（HR 0.89，0.47–1.69）與 OS（HR 0.76，0.34–1.66）的信賴區間很寬，論文結論寫「資料不足以評估存活」。

因為資料是模擬的，**真正的答案是已知的**——[demo/TRUTH.md](demo/TRUTH.md) 逐項比較：粗略比較差了 13 個百分點，
主分析的信賴區間全部涵蓋真值。

## 資料科學的規矩，落在哪些檔案

| 原則 | 這個 repo 怎麼做 |
|---|---|
| **單一來源（SSOT）** | 研究事實只在 [`config.toml`](config.toml)（IRB 表單與分析都讀它）；分析參數只在 [`analysis/params.yaml`](analysis/params.yaml)；期刊規定只在 [`manuscript/journal.yaml`](manuscript/journal.yaml)；示範腳本只在 [`demo/stages.toml`](demo/stages.toml) |
| **不重複（DRY）** | 治療分組、pCR、HER2、藥名對照只定義一次：[`analysis/R/definitions.R`](analysis/R/definitions.R)、[`analysis/drug_map.csv`](analysis/drug_map.csv) |
| **可稽核** | 原始資料只進 checksum（[`data/raw/MANIFEST.sha256`](data/raw/MANIFEST.sha256)）；資訊室更正以紀錄套用、原檔不動；每份結果記錄 git commit、資料指紋、軟體版本（[`results/provenance/`](results/provenance/)）；決策與理由在 [`analysis/decision_log.md`](analysis/decision_log.md) |
| **先驗證再分析** | [`results/data_validation.md`](results/data_validation.md)：欄位、範圍、重複、日期先後，錯誤未解決不進分析；定義有自動化測試（`make test-analysis`） |
| **數字不手打** | 論文裡每個數字由 `results/` 自動帶入；投稿前 [`submission/check_report.md`](submission/check_report.md) 自動檢查字數、格式、匿名化 |
| **個資** | 讀資料第一步就去識別化；病歷號對照表放在專案外；`data/`、`inbox/` 不進 git |

## 自己重現一次

需要 [uv](https://docs.astral.sh/uv/)、R 4.5（survival、WeightIt、MatchIt、cobalt、mice、EValue、gtsummary、ggplot2）、Quarto、LibreOffice。

```sh
uv sync
make demo-data    # 從種子重建模擬的院內資料，checksum 必須與 MANIFEST 一致
make analysis     # 從原始資料重跑：資料檢查 → 去識別化 → 收案 → Table 1 → 主分析 → 事後分析
make manuscript   # 產生論文與投稿檔（不改 submission/，要寫入用 make submission）
```

錄影怎麼做、怎麼重錄：[demo/README.md](demo/README.md)。

## 專案結構

```
config.toml, cv.toml, 中文計畫摘要.md   研究事實（IRB 表單的來源）
研究構想.md                           醫師的一頁筆記（一切的起點）
correspondence/                       與 IRB、資訊室、期刊的往來
analysis/                             分析計畫、參數、R 程式、測試、決策紀錄
results/                              表、圖、數字（只有彙總結果）
manuscript/                           Quarto 原稿、文獻清單與查證紀錄、期刊規定
submission/                           投稿包、revision1/、revision2/
institutions/, scripts/               IRB 表單產生器（來自 irb-in-hurry）
demo/                                 錄影機制、模擬資料產生器、外部來信、播放頁
```

## 致謝

- IRB 表單流程來自 [htlin222/irb-in-hurry](https://github.com/htlin222/irb-in-hurry)（原說明：[README.irb-in-hurry.md](README.irb-in-hurry.md)）
- 章節式錄影的想法來自 [htlin222/stagecast](https://github.com/htlin222/stagecast)；本 repo 改成**單一連續 session + Stop hook + asciinema marker**，章與章之間不 `/exit`
- 錄影中的 AI：Claude Code（Claude Opus 5.5）；文獻搜尋：OpenEvidence
