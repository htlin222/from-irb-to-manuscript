# 論文示範稿（JCRP 原著論文）

> ⚠️ **本示範稿由 AI（Claude Opus 5.5）撰寫，僅供教學。真實投稿時，論文內文必須由作者親自撰寫。**
> 期刊 *Journal of Cancer Research and Practice* 規定生成式 AI 不得撰寫論文或其相當部分（如方法、結果、分析），
> 違者以學術不端處理；AI 協助的用途須具名揭露。本稿所有資料皆為模擬（synthetic data for teaching）。

## 這個資料夾在做什麼

把 `results/` 的分析結果組成 JCRP 格式的兩個投稿檔（首頁檔＋匿名正文檔），並自動檢查投稿規定。

| 檔案 | 內容 | 誰寫 |
|---|---|---|
| `text/*.md` | 摘要、前言、方法、結果、討論、聲明、圖說 | **示範稿：AI；真實投稿：作者** |
| `meta.yaml` | 首頁資訊（短標題、關鍵字、作者學位與單位、經費、利益衝突、作者貢獻） | 示範稿：AI 以虛構資料填寫；真實投稿：作者 |
| `journal.yaml` | JCRP 投稿須知整理（字數、格式、表格、參考文獻、必要聲明） | 依期刊官方頁面整理 |
| `references.yaml` | 參考文獻清單（DOI）；`make references` 向 Crossref／PubMed 查證並產生 `references.json` | 文獻由 OpenEvidence 搜尋，逐篇查證 |
| `R/tokens.R` | 數字代號：正文寫 `{{pcr_or}}`，產生時自動帶入 `results/` 的數值（數字不手打） | 程式 |
| `R/tables.R`、`article.qmd`、`title_page.qmd` | 表 1–3、匿名正文、首頁 | 程式 |
| `R/check.R` | 投稿規定檢查（字數、表格大小、雙盲、文獻查證、用詞、必要聲明、圖檔） | 程式 |
| `writing_guide.qmd` | 給作者的中文寫作指引（STROBE 對照、代號表、建議引用、研究限制） | 程式產生 |

## 指令

```bash
make references    # 查證參考文獻（需網路）
make manuscript    # 產生草稿與檢查報告 → manuscript/_build/
make submission    # 所有檢查通過才寫入 submission/
```

## 真實投稿前必須做的事

1. 由作者親自重寫 `text/` 下全部正文，並讀過每篇引用文獻的原文。
2. 依實際情況撰寫 `meta.yaml`（真實單位、學位、經費、利益衝突、作者貢獻）。
3. 依實際 AI 使用情況改寫「Use of Generative AI」聲明，並移除論文與首頁上的「written by AI」示範標示。
4. 移除「synthetic data for teaching」標示前，確認使用的是真實、經 IRB 核准的資料。
