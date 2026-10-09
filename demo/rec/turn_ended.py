#!/usr/bin/env python3
"""Stop hook: a turn just ended. Record WHEN, and WHICH message it answered.

Writes to $DEMO_STATE:
  turns.jsonl        one line per ended turn: {"t": epoch, "id": stage id or null}
  answered/<id>      exists once the turn that received stage <id>'s prompt ended
  fp-<id>            fingerprint of the study repo at that moment (for `check edited`)

The end times are what the recording is cut against: chapters are marked where
each prompt was sent (drive.py) and the take ends where the last turn ended,
so the session never has to /exit and the final screen stays on.
"""

import json
import os
import pathlib
import subprocess
import sys
import time
import tomllib

state = pathlib.Path(os.environ["DEMO_STATE"])
home = pathlib.Path(os.environ["DEMO_HOME"])
ev = json.load(sys.stdin)
now = time.time()

stages = tomllib.loads(pathlib.Path(os.environ.get("DEMO_STAGES", home / "stages.toml")).read_text())["stage"]
wanted = {s["id"]: s["prompt"].strip() for s in stages}
said = state / "said.jsonl"
if said.exists():
    for line in said.read_text().splitlines():
        d = json.loads(line)
        wanted[d["id"]] = d["text"].strip()


def texts(entry):
    c = entry.get("message", {}).get("content")
    if isinstance(c, str):
        yield c
    elif isinstance(c, list):
        for b in c:
            if isinstance(b, dict) and b.get("type") == "text":
                yield b.get("text", "")


hit = None
for line in reversed(pathlib.Path(ev["transcript_path"]).read_text().splitlines()):
    try:
        e = json.loads(line)
    except ValueError:
        continue
    if e.get("type") != "user" or e.get("isMeta") or e.get("isCompactSummary"):
        continue
    body = " ".join(texts(e)).strip()
    if not body:
        continue  # tool results carry no text block
    hit = next((k for k, v in wanted.items() if body.startswith(v) or body == v), None)
    break  # only the most recent human message counts

(state / "answered").mkdir(parents=True, exist_ok=True)
if hit:
    fp = subprocess.run(
        [str(home / "rec" / "check"), "fp"], cwd=ev.get("cwd", "."), capture_output=True, text=True
    ).stdout.strip()
    (state / f"fp-{hit}").write_text(fp)
    (state / "answered" / hit).write_text(str(int(now)))
with (state / "turns.jsonl").open("a") as f:
    f.write(json.dumps({"t": now, "id": hit}) + "\n")
(state / "turn-ended").write_text(str(now))
