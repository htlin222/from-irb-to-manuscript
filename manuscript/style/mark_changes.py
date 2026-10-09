"""Mark changes between two versions of the manuscript text (Markdown) for a revised submission.

New text gets the Word character style "Inserted Text" (blue, underlined) and deleted text "Deleted Text"
(red, struck through), both defined in style/reference.docx (JCRP: "mark the changes as underlined or colored
text"). Citation groups ([@a; @b]) are compared as whole tokens named by their content, so the same citation
matches across versions; deleted citations are dropped so that they do not add references.

Also writes changes.json: one entry per changed paragraph with its section, subsection and the first words of
the change, so that the response letter can give the page of every change in the marked manuscript.

Usage: uv run python manuscript/style/mark_changes.py <old_dir> <new_dir> <out_dir>
"""
import difflib
import json
import re
import sys
from pathlib import Path

CITE = re.compile(r"\[@[^\]]*\]")
OPEN, CLOSE = "⟦", "⟧"   # 引用的代號外框（正文不會出現的字元）


def protect(text):
    """Each citation group becomes one token named by its keys, preceded by a space."""
    table = {}

    def sub(m):
        key = OPEN + re.sub(r"[\s@;]+", ",", m.group(0)[2:-1]).strip(",") + CLOSE
        table[key] = m.group(0)
        return " " + key
    return CITE.sub(sub, text), table


def restore(text, table):
    for key, cite in table.items():
        text = text.replace(" " + key, cite).replace(key, cite)
    return text


def is_cite(word):
    return word.startswith(OPEN)


def span(words, style):
    return f'[{" ".join(words)}]{{custom-style="{style}"}}'


def inserted(words):
    if words and all(is_cite(w) for w in words):   # 只新增引用：直接放上（引用編號無法加上樣式）
        return " ".join(words)
    return span(words, "Inserted Text") if words else ""


def deleted(words):
    kept = [w for w in words if not is_cite(w)]
    return span(kept, "Deleted Text") if kept else ""


def snippet(words):
    """First words of a change, as plain text that pdftotext will reproduce."""
    plain = [re.sub(r"[*_`]", "", w) for w in words if not is_cite(w)]
    return " ".join(w for w in plain if w)[:60]


def mark_paragraph(old, new):
    """Return (marked paragraph, snippet of the first change or None)."""
    if old == new:
        return new, None
    head = re.match(r"^(#+ )", new) or re.match(r"^(#+ )", old)
    prefix = head.group(1) if head else ""
    (o, ot), (n, nt) = protect(old[len(prefix):]), protect(new[len(prefix):])
    ow, nw = o.split(), n.split()
    out, first = [], None
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, ow, nw, autojunk=False).get_opcodes():
        if tag == "equal":
            out.append(" ".join(nw[j1:j2]))
            continue
        if tag in ("delete", "replace"):
            out.append(deleted(ow[i1:i2]))
            first = first or snippet(ow[i1:i2]) or None
        if tag in ("insert", "replace"):
            out.append(inserted(nw[j1:j2]))
            first = first or snippet(nw[j1:j2]) or None
    return prefix + restore(" ".join(x for x in out if x), {**ot, **nt}), first


def paragraphs(text):
    return [p.strip() for p in re.split(r"\n\s*\n", text.strip()) if p.strip()]


def mark(old_text, new_text, section=""):
    """Return (marked Markdown, list of changes with section, subsection and snippet)."""
    old_p, new_p = paragraphs(old_text), paragraphs(new_text)
    pairs = []   # (old paragraph, new paragraph) in reading order
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, old_p, new_p, autojunk=False).get_opcodes():
        if tag == "equal":
            pairs += [(p, p) for p in new_p[j1:j2]]
        elif tag == "insert":
            pairs += [("", p) for p in new_p[j1:j2]]
        elif tag == "delete":
            pairs += [(p, "") for p in old_p[i1:i2]]
        else:
            for k in range(max(i2 - i1, j2 - j1)):
                pairs.append((old_p[i1 + k] if i1 + k < i2 else "", new_p[j1 + k] if j1 + k < j2 else ""))
    out, changes, subsection = [], [], ""
    for old, new in pairs:
        heading = re.match(r"^#+ (.*)$", new or old)
        if heading:
            subsection = heading.group(1)
        marked, first = mark_paragraph(old, new)
        out.append(marked)
        if first:   # 頁碼用段落開頭定位（比修改處的片段更獨特）
            lead = snippet(protect(re.sub(r"^#+ ", "", new or old))[0].split())
            changes.append({"section": section, "subsection": subsection, "snippet": lead, "change": first})
    return "\n\n".join(p for p in out if p) + "\n", changes


if __name__ == "__main__":
    old_dir, new_dir, out_dir = map(Path, sys.argv[1:4])
    out_dir.mkdir(parents=True, exist_ok=True)
    all_changes = []
    for f in sorted(new_dir.glob("*.md")):
        old = (old_dir / f.name).read_text(encoding="utf-8") if (old_dir / f.name).exists() else ""
        marked, changes = mark(old, f.read_text(encoding="utf-8"), section=f.stem)
        (out_dir / f.name).write_text(marked, encoding="utf-8")
        all_changes += changes
    (out_dir / "changes.json").write_text(json.dumps(all_changes, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{len(all_changes)} changed paragraphs")
