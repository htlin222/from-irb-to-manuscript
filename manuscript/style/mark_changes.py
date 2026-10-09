"""Mark changes between two versions of the manuscript text (Markdown) for a revised submission.

New text is wrapped as [text]{.underline}; deleted text as ~~text~~ (JCRP: "mark the changes as underlined or
colored text"). Citations ([@key] groups) are kept intact; deleted citations are dropped so that they do not
create references.

Usage: uv run python manuscript/style/mark_changes.py <old_dir> <new_dir> <out_dir>
"""
import difflib
import re
import sys
from pathlib import Path

CITE = re.compile(r"\[@[^\]]*\]")


def protect(text):
    """Turn each citation group into its own token named by its content, so the same citation matches across versions."""
    table = {}

    def sub(m):
        key = "\u27e6" + re.sub(r"[\s@;]+", ",", m.group(0)[2:-1]).strip(",") + "\u27e7"
        table[key] = m.group(0)
        return " " + key
    return CITE.sub(sub, text), table


def restore(text, table):
    for key, cite in table.items():
        text = text.replace(" " + key, cite).replace(key, cite)
    return text


def ins(words):
    if words and all(w.startswith("\u27e6") for w in words):   # 只新增引用：直接放上（引用編號無法加底線）
        return " ".join(words)
    return f"[{' '.join(words)}]{{.underline}}" if words else ""


def dele(words):
    kept = [w for w in words if not re.fullmatch(r"⟦CITE\d+⟧[.,;:]?", w)]
    kept = [re.sub(r"⟦CITE\d+⟧", "", w) for w in kept]
    return f"~~{' '.join(kept)}~~" if any(kept) else ""


def mark_paragraph(old, new):
    if old == new:
        return new
    head = re.match(r"^(#+ )", new) or re.match(r"^(#+ )", old or "")
    prefix = head.group(1) if head else ""
    o, n = old[len(prefix):] if old else "", new[len(prefix):] if new else ""
    (o, oc), (n, nc) = protect(o), protect(n)
    nc = {**oc, **nc}
    ow, nw = o.split(), n.split()
    out = []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, ow, nw, autojunk=False).get_opcodes():
        if tag == "equal":
            out.append(" ".join(nw[j1:j2]))
        else:
            if tag in ("delete", "replace"):
                out.append(dele(ow[i1:i2]))
            if tag in ("insert", "replace"):
                out.append(ins(nw[j1:j2]))
    return prefix + restore(" ".join(x for x in out if x), nc)


def paragraphs(text):
    return [p.strip() for p in re.split(r"\n\s*\n", text.strip()) if p.strip()]


def mark(old_text, new_text):
    op, np_ = paragraphs(old_text), paragraphs(new_text)
    out = []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, op, np_, autojunk=False).get_opcodes():
        if tag == "equal":
            out += np_[j1:j2]
        elif tag == "insert":
            out += [mark_paragraph("", p) for p in np_[j1:j2]]
        elif tag == "delete":
            out += [mark_paragraph(p, "") for p in op[i1:i2]]
        else:
            pairs = max(i2 - i1, j2 - j1)
            for k in range(pairs):
                old = op[i1 + k] if i1 + k < i2 else ""
                new = np_[j1 + k] if j1 + k < j2 else ""
                out.append(mark_paragraph(old, new))
    return "\n\n".join(p for p in out if p) + "\n"


if __name__ == "__main__":
    old_dir, new_dir, out_dir = map(Path, sys.argv[1:4])
    out_dir.mkdir(parents=True, exist_ok=True)
    for f in sorted(new_dir.glob("*.md")):
        old = (old_dir / f.name).read_text(encoding="utf-8") if (old_dir / f.name).exists() else ""
        (out_dir / f.name).write_text(mark(old, f.read_text(encoding="utf-8")), encoding="utf-8")
        print(f.name)
