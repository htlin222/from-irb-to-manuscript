# 從 IRB 到投稿：HER2 陽性乳癌術前抗 HER2 治療（教學示範）

醫師的研究筆記在 `研究構想.md`。這個專案從 IRB 送審一路做到期刊投稿。
⚠️ 所有人名、單位、病人資料都是虛構／模擬的；任何對外文件（論文、投稿檔）都要清楚標示
「synthetic data for teaching」，不得讓人誤以為是真實研究。

## 怎麼跟醫師說話

- 一律用繁體中文、白話。對方是臨床醫師，不熟程式也不熟統計。
- 專有名詞第一次出現時，附一句白話解釋。
- 資訊足夠就直接做；只有真的需要醫師決定的事才問，問的時候給 2–4 個選項並標出你的建議。
- 做完一步，用幾句話說：做了什麼、產出在哪裡、下一步是什麼。

## 資料夾：每樣東西只有一個家

| 位置 | 放什麼 | 進 git？ |
|---|---|---|
| `inbox/` | 外面送來的檔案（IRB 審查意見、資訊室的資料、期刊審稿意見）。暫存區，處理完搬走 | 否 |
| `correspondence/` | 與 IRB、期刊往來的文件（意見、回覆、信件） | 是 |
| `data/raw/` | 院內原始資料。**唯讀、永不修改**；只把 SHA-256 記在 `data/raw/MANIFEST.sha256` | 否（只進 MANIFEST） |
| `data/derived/` | 程式產生的分析資料集，隨時可重建 | 否 |
| `analysis/` | 分析程式與分析參數 | 是 |
| `results/` | 程式產生的表、圖、數字（只有彙總結果，沒有個別病人資料） | 是 |
| `manuscript/` | 論文原稿 | 是 |
| `submission/` | 依期刊格式自動產生的投稿檔，不手改 | 是 |
| `output/` | IRB 表單（`make all` 產生） | 否 |

## 資料科學的五條規矩

1. **單一來源（SSOT）**：一個事實只寫在一個地方。研究事實（題目、收案期間、人員）在
   `config.toml`；分析參數在 `analysis/` 底下的一個設定檔。其他地方一律讀取，不抄寫。
2. **不重複（DRY）**：共用定義（pCR 的定義、藥名對照、終點事件的定義）只寫一次，其他程式引用。
3. **可稽核**：原始資料有 checksum；每次分析記錄當時的 git commit、資料 checksum、軟體版本。
   每張表、每張圖、每個數字都能追到產生它的程式。
4. **先驗證再分析**：資料進來先過檢查（欄位、範圍、重複、日期先後）；檢查不過就停下來告訴醫師。
   關鍵的推導（治療分組、pCR、存活時間）要有自動化測試。
5. **數字不手打**：論文裡的每個數字都從 `results/` 的機器可讀檔自動帶入。

其他規矩：
- 去識別化在讀資料的第一步完成；之後的檔案不得出現病歷號、生日。
- 統計：先寫分析計畫再看結果；之後改計畫要記錄理由。
- 參考文獻必須真實存在：每篇都要有 PMID 或 DOI，並查證過（PubMed / Crossref）。不可編造。
- `make` 是唯一入口：`make analysis` 從原始資料重跑全部分析，`make manuscript` 產生論文與投稿檔。
- 重要節點用 git commit 存檔，送審／投稿版本打 tag。

## 工具

- IRB 表單：Python（`uv`），見下方 IRB-in-Hurry 說明。
- 統計：R 4.5（已安裝 survival、WeightIt、MatchIt、cobalt、EValue、gtsummary、ggplot2、survminer、tableone）。
- 論文：Quarto（`quarto render`）→ Word。
- 文獻：OpenEvidence（`mcp__openevidence__*` 工具）。

---

# IRB-in-Hurry

Institution-agnostic IRB form pipeline: study facts (`config.toml`) + an
institution profile (`institutions/<id>/`) → that institution's official DOCX
forms → PDF → layout gate. KFSYSCC is the reference pack (`institutions/kfsyscc/`).
Method: `docs/METHODOLOGY.md` · Fork guide: `docs/ONBOARDING.md`.

## Quick Start

```bash
# Edit config.toml (facts, `institution = "<id>"`), cv.toml (team), 中文計畫摘要.md (prose)
make check                        # Resolve @references + validate
make templates                    # Once: cache the institution's blank forms
make all                          # Generate + PDF + layout gate + dashboard
make closure                      # = make all PHASE=closure (any phase; file untouched)
make set-phase PHASE=closure      # Persist the phase in config.toml (keeps comments)
make onboard INST=<id>            # New institution: blanks in templates/<id>/ → draft pack
```

## Conventions

- **Python**: Managed by `uv` (pyproject.toml), run via `uv run` or `make`
- **Three kinds of data, never mixed**:
  - study facts → `config.toml` (+ the files it `@`-references)
  - institution facts (names, IRB-no label, submission address, page, margins, font, blank locations) → `institutions/<id>/profile.toml`
  - form list + routing → `institutions/<id>/forms.py`
- **No institution literals in code**: generators read `institution()` (`scripts.docx_utils`); shared scripts read `scripts.institution.current()`
- **Active institution**: `IRB_INSTITUTION` env → `institution` in config.toml → `kfsyscc`
- **Generators**: prefer `template_fill.blank_generator` (fill the official blank); rebuild with python-docx only when a blank can't be filled
- **Font**: the profile's `font` (KFSYSCC: 標楷體 / DFKai-SB); no theme fonts (`pin_form_font`)
- **Checkbox**: ■ (U+25A0) = checked, □ (U+25A1) = unchecked, via `check()`
- **Config (SSOT)**: All study data in plain text, never hardcoded. `config.toml` holds
  structured fields; `"@file"` / `"@file#key"` values inline other files (`@cv.toml#pi`,
  `@中文計畫摘要.md`). Long prose goes in Markdown (`## 標題` → section key), not TOML strings.
  Loader + validation: `scripts/config.py`. Never re-dump config.toml — use `PHASE=` for a
  one-off run, or `set_phase.py` (edits only the `phase =` line) to persist it
- **Output**: DOCX → `output/`, PDF → `output/`, PNG previews → `output/preview/`
- **Page**: profile page size + per-form margins, applied by `generate_all`
- **Blanks**: `templates/<id>/` (gitignored), the gate's ground truth, never edited
- **Layout gate**: `make validate` must show 0 errors before submission; PDF is the submission copy

## Project Structure

- `institutions/<id>/` — profile.toml, forms.py, form_inventory.md (one folder per committee)
- `scripts/institution.py` — Active profile loader
- `scripts/config.py` — config.toml loader (`@` references, Markdown sections, `make check`) + validation: required fields, enums, real booleans, defaults for optional sections
- `scripts/template_fill.py` — Generic fill-the-blank generator (labels → values, □ → ■)
- `scripts/onboard.py` — Blank forms → draft profile + forms.py + inventory
- `scripts/docx_utils.py` — Shared DOCX helpers (profile-aware; `form_filename` for output names)
- `scripts/form_selector.py` — Phase + study type → required forms (active pack); shared `PHASE_NAMES`
- `scripts/generators/` — KFSYSCC rebuild generators (reference pack)
- `scripts/generate_all.py` — Main orchestrator (`--phase`, `--output`, `--verbose`)
- `scripts/set_phase.py` — Persist `phase = "..."` in config.toml without losing comments (`make set-phase`)
- `scripts/checklist.py` — ■/□ checklist generator
- `scripts/convert.py` — DOCX→PDF→PNG pipeline
- `scripts/fetch_templates.py` — Scrape or index official blanks → `templates/<id>/`
- `scripts/validate_layout.py` — Layout/font safety gate → `output/layout_report.md`
- `examples/` — Complete example studies (`make init EXAMPLE=tdxd-her2low`)
- `.claude/skills/irb/` — Claude Code skill set (onboarding: `references/onboard-institution.md`)

## Testing

```bash
make init EXAMPLE=gcsf-retrospective FORCE=1 && make all
make test   # every example × every phase, config validation, layout gate
make lint   # ruff; CI runs both on every PR
```

New generator: add it to `FORM_REGISTRY` in `institutions/<id>/forms.py`; the e2e matrix
picks it up automatically. New config field: document it in
`.claude/skills/irb/references/config-schema.md`, and add it to `DEFAULTS` /
`BOOL_FIELDS` in `scripts/config.py` if generators index it directly.
