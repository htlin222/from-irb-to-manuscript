#!/usr/bin/env python3
"""Fill template.html from stages.toml + chapters.json, and write PROMPTS.md.

    build_site.py SITE_DIR [--prompts-md PATH]

stages.toml is the single source of the prompts: the published page and
PROMPTS.md are both generated from it, so they cannot drift apart.
"""

from __future__ import annotations

import argparse
import html
import json
import os
import tomllib
from pathlib import Path

HERE = Path(__file__).resolve().parent
STAGES = Path(os.environ.get("DEMO_STAGES", HERE.parent / "stages.toml"))

ABOUT = """
<p><b>這是一段沒有剪接的錄影。</b>一位醫師（由程式代打）把一句一句很短的話送進 Claude Code，
從 IRB 新案送審、審查意見、複審、拿到院內資料、資料檢查、公平比較兩種治療、寫論文、投稿，
一路到期刊審稿來回與接受。全部在<b>同一個對話</b>裡完成。</p>

<h2>怎麼看</h2>
<p>左邊每一章就是一句送出的話。每一章先顯示這一句寫了什麼，按 START 播放；AI 回答完會停在最後的畫面，按「下一章」再往下。<b>空白鍵</b>就是「下一步」：開始播放 → 暫停／繼續 → 下一章。
不想停，把下方「每章停下來看題目」取消勾選。想先讀完上一章的回答，按「先看上一章的回答」。</p>
<p><b>縮時</b>：每一輪開頭 20 秒（訊息送進去）與結尾 15 秒（答案出來）是原速；中間 AI 在工作的片段以 8 倍速播放，
畫面停滯超過 2 秒的地方也壓到 2 秒。實際錄影長度見右上角。標著「↳ 補充一句」的是 AI 停下來需要回應時，錄影者補上的話，照實保留。</p>

<h2>怎麼錄的</h2>
<p>只開一次 Claude Code，章與章之間<b>從不 <code>/exit</code></b>，所以畫面不會消失。
每一章的起點是送出那句話的時間；每一輪的終點由 Claude Code 的 <b>Stop hook</b> 記錄。
兩組時間在錄完後寫進 asciinema 的 <b>marker</b>，就是左邊的章節。</p>
<p>一章要進到下一章，必須同時滿足兩件事：那一輪真的結束（Stop hook），而且該有的產物真的存在
（例如 PDF、git 標籤、資料 checksum、投稿檔）。只聽 AI 說「完成了」不算數。</p>

<h2>資料是假的</h2>
<p>所有病人、人名、單位、IRB 編號與期刊往來信件都是<b>模擬</b>的。
病人資料由程式產生，而且產生時就知道「真正的答案」，所以可以回頭檢查 AI 選的統計方法有沒有估對——
見 repo 裡的 <code>demo/TRUTH.md</code>。</p>
"""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("site")
    ap.add_argument("--prompts-md")
    a = ap.parse_args()
    cfg = tomllib.loads(STAGES.read_text())
    proj = cfg["project"]
    site = Path(a.site)
    chapters = json.loads((site / "chapters.json").read_text())
    stages = [c for c in chapters if c["kind"] == "stage"]
    says = [c for c in chapters if c["kind"] == "say"]
    total = max((c.get("end") or c["t"]) for c in chapters) if chapters else 0

    raw = json.loads((site / "meta.json").read_text())["raw_seconds"] if (site / "meta.json").exists() else total
    facts = [
        (str(len(stages)), "句 prompt"),
        (str(len(says)), "句補充"),
        (f"{raw / 3600:.1f} h", "實際時間"),
        (f"{total / 60:.0f} min", "縮時播放"),
    ]
    facts_html = "".join(f"<div><b>{html.escape(v)}</b><span>{html.escape(k)}</span></div>" for v, k in facts)
    keys = [
        "IRB",
        "inbox",
        "Table 1",
        "pCR",
        "EFS",
        "OS",
        "OpenEvidence",
        "cover letter",
        "「IRB 初審」",
        "「IRB 複審」",
        "「分析完成」",
        "「投稿版」",
        "「第一次修訂」",
        "「第二次修訂」",
    ]
    page = (HERE / "template.html").read_text()
    for k, v in {
        "{{TITLE}}": html.escape(proj["title"]),
        "{{NAME}}": html.escape(proj["title"]),
        "{{BLURB}}": html.escape(proj["blurb"]),
        "{{FACTS}}": facts_html,
        "{{REPO}}": proj["repo"],
        "{{ABOUT}}": ABOUT,
        "{{CHAPTERS}}": json.dumps(chapters, ensure_ascii=False),
        "{{KEYS}}": json.dumps(keys, ensure_ascii=False),
    }.items():
        page = page.replace(k, v)
    (site / "index.html").write_text(page)
    print(f"site: {site / 'index.html'} ({len(stages)} chapters, {len(says)} interjections)")

    if a.prompts_md:
        lines = [
            "# PROMPTS — 示範腳本",
            "",
            "一行一句，依序貼進 Claude Code。全部刻意寫短、不用專有名詞；",
            "統計方法不是由醫師指定，而是先問「有哪些方法」再選。",
            "",
            "> 由 `demo/stages.toml` 自動產生，請改那個檔，不要改這裡。",
            "",
        ]
        part = None
        for s in cfg["stage"]:
            if s["part"] != part:
                part = s["part"]
                lines += ["", f"## {part}", ""]
            drop = f"　〔inbox 收到：{'、'.join(Path(d).name for d in s['drop'])}〕" if s.get("drop") else ""
            lines.append(f"{s['id']}. {s['prompt']}{drop}")
            if s.get("recorded"):
                lines.append(
                    f"    - 錄影時只送了「{s['recorded']}」，AI 停下來問，錄影者補了下面這句；上面的 prompt 已把它併進來，現場不用再補"
                )
            for c in says:
                if c.get("after") == s["id"]:
                    lines.append(f"    - ↳ 補充一句（錄影時臨場補上）：{c['prompt']}")
        Path(a.prompts_md).write_text("\n".join(lines) + "\n")
        print(f"prompts: {a.prompts_md}")


if __name__ == "__main__":
    main()
