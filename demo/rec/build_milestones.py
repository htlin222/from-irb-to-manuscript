#!/usr/bin/env python3
"""Build the player page's milestone gallery from demo/milestones.toml.

    build_milestones.py SITE_DIR [--templates DIR]

Every file is taken from the git version named in milestones.toml (never from
the working tree), so a milestone shows exactly what existed at that point.
Files are turned into something a browser can show:

    pdf, png, jpg      copied as is
    md                 pandoc → HTML page (the .md is kept for download)
    csv                HTML table (the .csv is kept for download)
    text               HTML <pre>
    docx               LibreOffice → PDF preview (the .docx is kept for download)
    raw                first rows of the synthetic hospital extract (make demo-data)
    irb                IRB forms regenerated at that version (output/ is not in git)

Writes SITE_DIR/milestones/<id>/… and SITE_DIR/milestones.json.
"""

from __future__ import annotations

import argparse
import csv
import html
import io
import json
import shutil
import subprocess
import tempfile
import tomllib
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[2]
CFG = tomllib.loads((ROOT / "demo" / "milestones.toml").read_text())
REPO = tomllib.loads((ROOT / "demo" / "stages.toml").read_text())["project"]["repo"]
RAW_ROWS = 15
CSV_ROWS = 120

PAGE = """<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>{title}</title>
<style>
:root {{ --ink:#1c1917; --muted:#57534e; --line:#e7e5e4; --soft:#fafaf9; }}
body {{ margin:0; padding:24px 28px 48px; background:#fff; color:var(--ink);
  font:15px/1.7 ui-sans-serif,-apple-system,"PingFang TC","Noto Sans TC",sans-serif; }}
main {{ max-width:880px; margin:0 auto; }}
h1,h2,h3 {{ line-height:1.35; }} h1 {{ font-size:22px; }} h2 {{ font-size:18px; margin-top:28px; }}
a {{ color:var(--ink); }}
table {{ border-collapse:collapse; font-size:13px; margin:12px 0; display:block; overflow-x:auto; }}
th,td {{ border:1px solid var(--line); padding:4px 8px; text-align:left; vertical-align:top; white-space:nowrap; }}
th {{ background:var(--soft); position:sticky; top:0; }}
pre,code {{ font:13px ui-monospace,"SF Mono",Menlo,monospace; }}
pre {{ background:var(--soft); padding:12px; overflow-x:auto; border-radius:4px; white-space:pre-wrap; }}
blockquote {{ margin:12px 0; padding:4px 14px; border-left:3px solid var(--line); color:var(--muted); }}
.note {{ color:var(--muted); font-size:13px; margin:0 0 14px; }}
.banner {{ background:#fff7ed; border:1px solid #fed7aa; color:#9a3412; padding:8px 12px; border-radius:4px;
  font-size:13px; margin-bottom:14px; }}
@media (max-width:600px) {{ body {{ padding:16px; }} }}
</style></head><body><main>{body}</main></body></html>"""


def git_bytes(ref: str, path: str) -> bytes:
    return subprocess.run(["git", "show", f"{ref}:{path}"], cwd=ROOT, capture_output=True, check=True).stdout


def page(title: str, body: str) -> str:
    return PAGE.format(title=html.escape(title), body=body)


def md_to_html(md: bytes, title: str) -> str:
    body = subprocess.run(
        ["pandoc", "-f", "gfm", "-t", "html"], input=md, capture_output=True, check=True
    ).stdout.decode()
    return page(title, body)


def table_html(text: str, limit: int, banner: str = "") -> str:
    rows = list(csv.reader(io.StringIO(text)))
    head, data = rows[0], rows[1:]
    note = f"共 {len(data)} 列 × {len(head)} 欄" + (f"，以下只顯示前 {limit} 列" if len(data) > limit else "")
    th = "".join(f"<th>{html.escape(h)}</th>" for h in head)
    trs = "".join("<tr>" + "".join(f"<td>{html.escape(c)}</td>" for c in r) + "</tr>" for r in data[:limit])
    return f'{banner}<p class="note">{note}</p><table><thead><tr>{th}</tr></thead><tbody>{trs}</tbody></table>'


def soffice_pdf(src: Path, outdir: Path) -> Path:
    with tempfile.TemporaryDirectory() as profile:
        subprocess.run(
            [
                "soffice",
                f"-env:UserInstallation=file://{profile}",
                "--headless",
                "--convert-to",
                "pdf",
                "--outdir",
                str(outdir),
                str(src),
            ],
            capture_output=True,
            check=True,
            timeout=300,
        )
    return outdir / (src.stem + ".pdf")


def pdf_preview(pdf: Path, title: str) -> str:
    """Page images + an HTML page that stacks them: every browser can show
    this, unlike an embedded PDF (no plugin in mobile Safari or headless)."""
    pages = pdf.with_suffix(".pages")
    pages.mkdir(exist_ok=True)
    subprocess.run(
        [
            "pdftoppm",
            "-jpeg",
            "-jpegopt",
            "quality=72",
            "-scale-to-x",
            "1100",
            "-scale-to-y",
            "-1",
            str(pdf),
            str(pages / "p"),
        ],
        check=True,
        capture_output=True,
    )
    imgs = sorted(pages.glob("p-*.jpg"))
    figs = "".join(
        f'<figure style="margin:0 0 18px"><img loading="lazy" alt="第 {k} 頁" '
        f'style="width:100%;box-shadow:0 0 0 1px var(--line)" src="{quote(pages.name)}/{i.name}">'
        f'<figcaption class="note" style="text-align:center">第 {k} 頁</figcaption></figure>'
        for k, i in enumerate(imgs, 1)
    )
    note = f'<p class="note">共 {len(imgs)} 頁 · <a href="{quote(pdf.name)}">開啟 PDF 原檔</a></p>'
    view = pdf.with_name(pdf.name + ".html")
    view.write_text(page(title, f"<h1>{html.escape(title)}</h1>{note}{figs}"))
    return view.name


def irb_forms(ref: str, phase: str, outdir: Path, templates: Path) -> list[Path]:
    """Regenerate the IRB forms exactly as the repo at `ref` would produce them."""
    with tempfile.TemporaryDirectory() as tmp:
        wt = Path(tmp) / "wt"
        subprocess.run(["git", "worktree", "add", "--detach", str(wt), ref], cwd=ROOT, capture_output=True, check=True)
        try:
            shutil.copytree(templates, wt / "templates")
            out = wt / "milestone_out"
            run = dict(cwd=wt, capture_output=True, check=True, timeout=900)
            subprocess.run(
                [
                    "uv",
                    "run",
                    "-q",
                    "python",
                    "scripts/generate_all.py",
                    "config.toml",
                    "--output",
                    str(out),
                    "--phase",
                    phase,
                ],
                **run,
            )
            subprocess.run(["uv", "run", "-q", "python", "scripts/convert.py", str(out)], **run)
            pdfs = sorted(out.glob("*.pdf"))
            for p in pdfs:
                shutil.copy2(p, outdir / p.name)
            return [outdir / p.name for p in pdfs]
        finally:
            subprocess.run(["git", "worktree", "remove", "--force", str(wt)], cwd=ROOT, capture_output=True)


def build_item(it: dict, ref: str, outdir: Path, n: int) -> dict:
    src = it["src"]
    name = Path(src.split(":", 1)[-1]).name
    stem = f"{n:02d}-{Path(name).stem}"
    ext = Path(name).suffix.lower().lstrip(".")
    kind = it.get("kind") or {
        "md": "md",
        "csv": "csv",
        "docx": "docx",
        "pdf": "file",
        "png": "image",
        "jpg": "image",
        "jpeg": "image",
    }.get(ext, "text")
    entry = {"label": it["label"], "kind": kind, "ref": ref, "src": src}
    if kind == "raw":
        data = (ROOT / "demo/simulate/out/export" / name).read_text()
        banner = (
            '<div class="banner">⚠️ 模擬資料（程式產生，不代表任何真實個人）。病歷號、生日也是假的。'
            "真實研究的原始資料永遠不會出現在網路上或 git 裡；完整檔案可用 <code>make demo-data</code> 重建。</div>"
        )
        (outdir / f"{stem}.html").write_text(
            page(name, f"<h1>{html.escape(name)}</h1>" + table_html(data, RAW_ROWS, banner))
        )
        entry |= {"view": f"{stem}.html", "src": f"make demo-data → data/raw/{name}"}
        return entry
    blob = git_bytes(ref, src)
    if kind == "md":
        (outdir / f"{stem}.md").write_bytes(blob)
        (outdir / f"{stem}.html").write_text(md_to_html(blob, it["label"]))
        entry |= {"view": f"{stem}.html", "download": f"{stem}.md"}
    elif kind == "csv":
        (outdir / f"{stem}.csv").write_bytes(blob)
        body = f"<h1>{html.escape(it['label'])}</h1>" + table_html(blob.decode("utf-8-sig"), CSV_ROWS)
        (outdir / f"{stem}.html").write_text(page(it["label"], body))
        entry |= {"view": f"{stem}.html", "download": f"{stem}.csv"}
    elif kind == "text":
        body = f"<h1>{html.escape(it['label'])}</h1><pre>{html.escape(blob.decode())}</pre>"
        (outdir / f"{stem}.html").write_text(page(it["label"], body))
        entry |= {"view": f"{stem}.html"}
    elif kind == "docx":
        docx = outdir / f"{stem}.docx"
        docx.write_bytes(blob)
        pdf = soffice_pdf(docx, outdir)
        entry |= {"view": pdf_preview(pdf, it["label"]), "pdf": pdf.name, "download": f"{stem}.docx"}
    else:  # file / image
        (outdir / f"{stem}.{ext}").write_bytes(blob)
        entry |= {"view": f"{stem}.{ext}"}
        if ext == "pdf":
            entry |= {"kind": "pdf", "view": pdf_preview(outdir / f"{stem}.pdf", it["label"]), "pdf": f"{stem}.pdf"}
    return entry


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("site")
    ap.add_argument(
        "--templates",
        default="/Users/Shared/her2-neoadjuvant-study/templates",
        help="cached IRB blank forms (make templates); needed to regenerate IRB PDFs",
    )
    a = ap.parse_args()
    site = Path(a.site)
    root_out = site / "milestones"
    shutil.rmtree(root_out, ignore_errors=True)  # a stale file is indistinguishable from a fresh one
    out_json = []
    for m in CFG["milestone"]:
        outdir = root_out / m["id"]
        outdir.mkdir(parents=True)
        items = []
        if "irb" in m:
            ref = m["irb"].get("ref", m["ref"])
            for p in irb_forms(ref, m["irb"]["phase"], outdir, Path(a.templates)):
                items.append(
                    {
                        "label": p.stem.replace("_", " "),
                        "group": m["irb"]["label"],
                        "kind": "pdf",
                        "ref": ref,
                        "view": pdf_preview(p, p.stem.replace("_", " ")),
                        "pdf": p.name,
                        "src": f"make all PHASE={m['irb']['phase']}",
                    }
                )
        for n, it in enumerate(m["items"], 1):
            items.append(build_item(it, it.get("ref", m["ref"]), outdir, n))
        tag = m["ref"]
        out_json.append(
            {
                "id": m["id"],
                "title": m["title"],
                "summary": m["summary"],
                "ref": tag,
                "tree": f"{REPO}/tree/{tag}",
                "chapters": m["chapters"],
                "items": items,
            }
        )
        print(f"{m['id']}: {len(items)} files")
    (site / "milestones.json").write_text(json.dumps(out_json, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
