# demo/ — 錄影怎麼做的

整個示範是**一段沒有剪接、只開一次的 Claude Code 對話**。這個資料夾放錄影機制、
模擬的外部來信、模擬資料產生器，以及發佈到 GitHub Pages 的播放頁。

| 檔案 | 用途 |
|---|---|
| `stages.toml` | **唯一來源**：每章的 prompt、送出前放進 inbox 的檔案、完成檢查。`PROMPTS.md` 與播放頁都由它產生 |
| `drops/` | 模擬「外面寄來的東西」：IRB 審查意見、核准通知、資訊室資料說明、期刊三輪來信 |
| `simulate/simulate_export.py` | 產生模擬的院內資料匯出（4 個 CSV）與 `truth.json`（真正的因果效果） |
| `rec/agent.sh` | 啟動被錄的 Claude Code：只讀專案設定（`--setting-sources project,local`）、淺色主題、OpenEvidence MCP |
| `rec/turn_ended.py` | **Stop hook**：每輪結束時記下時間、以及這一輪回答的是哪一章 |
| `rec/check` | 每章的完成檢查（輪次結束、git 標籤、檔案、資料 checksum…） |
| `rec/drive.py` | 驅動：`start` → `run` →（必要時 `say`）→ `finish` |
| `rec/postprocess.py` | 原始錄影 → 發佈用 cast：章節寫成 asciinema **marker**、壓縮閒置時間、遮蔽密鑰 |
| `rec/build_site.py` + `rec/template.html` | 產生播放頁與 `PROMPTS.md` |
| `milestones.toml` + `rec/build_milestones.py` | 播放頁的「里程碑成品」：每個階段的檔案，**取自當時的 git 標籤**；IRB 表單在該版本上重新產生，DOCX/PDF 轉成逐頁圖片預覽，CSV 轉表格、Markdown 轉網頁 |
| `TRUTH.md` | AI 的估計值 vs. 模擬時設定的真值 |
| `site/` | 發佈的播放頁（`index.html`、`demo.cast`、`chapters.json`） |

## 跟 irb-in-hurry 的錄法差在哪

irb-in-hurry 一章開一個 session、每章結尾 `/exit`，畫面在每章結尾被清掉。這裡：

- **從不 `/exit`**。章與章之間只是同一段對話的下一句，畫面一直都在。
- **章節 = marker**。驅動程式在送出每句話時記時間（`markers.jsonl`），
  Stop hook 在每輪結束時記時間（`turns.jsonl`）。錄完後 `postprocess.py` 把它們寫成 cast 裡的
  `"m"` 事件；播放器的 `pauseOnMarkers` 讓每章開頭停下來顯示題目。
- **錄影的結尾 = 最後一輪結束的時間**（Stop hook 記的），再多留幾秒。
  `finish` 先停 asciinema 再關 tmux，所以最後一格是 AI 的最後一段回答，而不是清空的畫面。
- 每一輪結束時，答案在畫面上固定停留 8 秒（`--hold`），下一章的題目卡才蓋上來。
- **分段載入**：`build_site.py` 另外切出 `demo.head.cast`（前 5 分鐘，約 130 KB gzip），首次載入先播它，完整的 `demo.cast` 在背景下載，趁暫停或題目卡時無縫換上。
- 播放器不設 `idleTimeLimit`：閒置已在後製壓過；播放器再壓一次會讓時間軸和 `chapters.json` 對不上，也會吃掉答案停留的 8 秒。
- 播放器不用 `poster` 選項：設了它之後，從 marker 開始播放不會重建之前的畫面（標頭與狀態列會消失）。
- 錄影用原始時間軸（`-i 86400`，不讓 asciinema 自己壓縮），好讓 hook 的時間戳對得上；
  閒置壓縮在後製時做。

## 完成訊號

一章要往下走，必須同時：(1) Stop hook 說「收到這一句的那一輪結束了」，
(2) 該章的 `verify` 通過（分支、PDF、git 標籤、`data/raw/MANIFEST.sha256`、投稿檔…）。
只聽 AI 說「完成了」不算數。若某輪結束但檢查不過（AI 停下來問問題或做一半），
驅動程式停下，由錄影者用 `drive.py say "…"` 補一句——播放頁會以「↳ 補充一句」照實標示。

AI 用選擇題反問時（AskUserQuestion），驅動程式扮演新手醫師：**選 AI 標示為推薦的選項**。

## 重錄

```sh
# 0. 需要：tmux、asciinema、uv、claude、R 4.5、quarto、LibreOffice
make demo-data                                       # 產生 demo/simulate/out/
git clone --branch demo-start . /Users/Shared/her2-neoadjuvant-study
git -C /Users/Shared/her2-neoadjuvant-study remote remove origin
(cd /Users/Shared/her2-neoadjuvant-study && uv sync && make templates)

export DEMO_STATE=$PWD/demo/.state
python3 demo/rec/drive.py start
python3 demo/rec/drive.py run          # 停下來時：drive.py say "…"，再 run
python3 demo/rec/drive.py finish
python3 demo/rec/postprocess.py demo/.state demo/site
python3 demo/rec/build_milestones.py demo/site --templates <IRB 空白表單快取>   # 需要 make demo-data、LibreOffice、pdftoppm
python3 demo/rec/build_site.py demo/site --prompts-md PROMPTS.md
```

工作目錄放在 `/Users/Shared/` 而不是家目錄底下，是刻意的：Claude Code 會讀取每一層上層目錄的
`CLAUDE.md`，錄影者個人的 `~/.claude/CLAUDE.md` 不該混進示範。
