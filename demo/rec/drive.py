#!/usr/bin/env python3
"""Drive ONE continuous Claude Code session through every chapter in stages.toml.

    drive.py start               open tmux + asciinema + Claude Code (once)
    drive.py run [--from ID]     send chapters in order; each advances only when
                                 its turn has ended AND its verify check passes
    drive.py say "text"          send an unscripted message (logged as a marker)
    drive.py finish              stop recording WITHOUT /exit, so the last
                                 screen stays on in the published cast
    drive.py status              what is done, what is next

Unlike a per-chapter recorder, nothing here quits the agent between chapters.
Chapter boundaries are kept as timestamps instead:
  markers.jsonl   written here when each prompt is sent   -> asciinema markers
  turns.jsonl     written by the Stop hook when each turn ends
postprocess.py turns both into "m" events in the cast.

Exit codes of `run`: 0 all done, 3 a turn ended but its check failed (the agent
stopped short or asked something -- answer with `say`, then `run` again),
1 stalled, 5 the terminal went away.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import tomllib
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEMO = HERE.parent
STAGES = Path(os.environ.get("DEMO_STAGES", DEMO / "stages.toml"))
CFG = tomllib.loads(STAGES.read_text())
REC = CFG["recording"]
SOCK = REC["socket"]
STATE = Path(os.environ.get("DEMO_STATE", DEMO / ".state"))
# Outside $HOME on purpose: Claude Code reads CLAUDE.md from every ancestor
# directory, and the recorder's personal ~/.claude/CLAUDE.md must not leak in.
WORK = Path(os.environ.get("DEMO_WORKDIR", Path("/Users/Shared") / CFG["project"]["workdir"]))
RAW = STATE / "raw.cast"


def log(msg: str) -> None:
    print(time.strftime("%H:%M:%S"), msg, flush=True)


def tmux(*args: str, check: bool = False) -> subprocess.CompletedProcess:
    return subprocess.run(["tmux", "-L", SOCK, *args], capture_output=True, text=True, check=check)


def pane() -> str:
    return tmux("capture-pane", "-p", "-t", SOCK).stdout


def alive() -> bool:
    return tmux("has-session", "-t", SOCK).returncode == 0


def jsonl_append(path: Path, obj: dict) -> None:
    with path.open("a") as f:
        f.write(json.dumps(obj, ensure_ascii=False) + "\n")


def verify(expr: str) -> bool:
    env = dict(os.environ, PATH=f"{HERE}:{os.environ['PATH']}", DEMO_STATE=str(STATE))
    return subprocess.run(["bash", "-c", expr], cwd=WORK, env=env, capture_output=True).returncode == 0


def settle(seconds: int = 3, limit: int = 60) -> None:
    prev, still = None, 0
    for _ in range(limit):
        now = pane()
        still = still + 1 if now == prev else 0
        prev = now
        if still >= seconds:
            return
        time.sleep(1)


# --------------------------------------------------------------------------- start
def cmd_start(_: argparse.Namespace) -> int:
    if alive():
        log("already running")
        return 0
    STATE.mkdir(parents=True, exist_ok=True)
    tmux(
        "new-session",
        "-d",
        "-s",
        SOCK,
        "-x",
        str(REC["cols"]),
        "-y",
        str(REC["rows"]),
        "-c",
        str(WORK),
        "-e",
        f"DEMO_STATE={STATE}",
        "-e",
        f"DEMO_STAGES={STAGES}",
        "-e",
        f"COLS={REC['cols']}",
        "-e",
        f"ROWS={REC['rows']}",
        f"bash '{HERE / 'record.sh'}'",
        check=True,
    )
    jsonl_append(STATE / "session.jsonl", {"t": time.time(), "event": "start"})
    for _ in range(60):
        screen = pane()
        # First launch in a new folder: trust + bypass-permissions confirmations.
        # They happen before the "ready" mark, so postprocess.py cuts them out.
        if "Allow external CLAUDE.md file imports" in screen:
            tmux("send-keys", "-t", SOCK, "Enter")
            time.sleep(3)  # default: No
            continue
        if "Yes, I trust this folder" in screen or "Yes, I accept" in screen:
            tmux("send-keys", "-t", SOCK, "Down")
            time.sleep(0.5)
            tmux("send-keys", "-t", SOCK, "Enter")
            time.sleep(3)
            continue
        if re.search(r"bypass permissions|for shortcuts|Try \"", screen):
            break
        time.sleep(2)
    else:
        log("✖ Claude Code did not come up:\n" + pane())
        return 5
    time.sleep(3)
    jsonl_append(STATE / "session.jsonl", {"t": time.time(), "event": "ready"})
    log("▶ session up")
    return 0


# --------------------------------------------------------------------------- send
def send(text: str) -> None:
    # The recorder's Claude Code may be in vim input mode: make sure we are in
    # INSERT before pasting (Escape would drop us into NORMAL).
    if "-- NORMAL --" in pane():
        tmux("send-keys", "-t", SOCK, "i")
        time.sleep(0.5)
    subprocess.run(["tmux", "-L", SOCK, "load-buffer", "-"], input=text, text=True, check=True)
    tmux("paste-buffer", "-p", "-t", SOCK)
    time.sleep(1.5)
    tmux("send-keys", "-t", SOCK, "Enter")
    # An Enter can be swallowed while the TUI is busy re-rendering: if the text is
    # still sitting in the input box a few seconds later, press it again.
    time.sleep(4)
    head = text.strip().splitlines()[0][:12]
    # The input box is the LAST "❯" line; earlier ones are the conversation.
    box = next((line for line in reversed(pane().splitlines()) if line.lstrip().startswith("❯")), "")
    if head and head in box:
        log("  (Enter again)")
        tmux("send-keys", "-t", SOCK, "Enter")


RECOMMEND = re.compile(r"Recommended|推薦|建議")


def answer_question(screen: str) -> bool:
    """Play the clinician at an AskUserQuestion prompt: take the recommended option.

    The demo's premise is a beginner who follows the expert's recommendation; when
    nothing is marked, take the first option. Returns True if a key was sent.
    """
    if "Enter to select" not in screen and "Submit answers" not in screen:
        return False
    if re.search(r"Submit answers|Review your answers", screen) and "Enter to select" not in screen:
        time.sleep(3)
        tmux("send-keys", "-t", SOCK, "Enter")
        log("  (responder) submitted answers")
        return True
    # Only the question widget: walk up from "Enter to select" to the rule line
    # above it, so numbered lists in the conversation are never read as options.
    lines = screen.splitlines()
    end = max(i for i, line in enumerate(lines) if "Enter to select" in line)
    begin = next((i for i in range(end, -1, -1) if re.fullmatch(r"\s*─{10,}.*", lines[i])), 0)
    opts = [line for line in lines[begin:end] if re.match(r"^\s*(❯\s*)?\d+\.\s", line)]
    pick = next((i for i, opt in enumerate(opts) if RECOMMEND.search(opt)), 0)
    time.sleep(6)  # give the viewer time to read the question
    for _ in range(pick):
        tmux("send-keys", "-t", SOCK, "Down")
        time.sleep(0.4)
    tmux("send-keys", "-t", SOCK, "Enter")
    log(f"  (responder) chose option {pick + 1}: {opts[pick].strip()[:60] if opts else '?'}")
    time.sleep(5)
    return True


def wait_turn(sid: str, check_expr: str | None) -> int:
    stall = REC.get("stall_minutes", 30) * 60
    last_rev, last_change = None, time.time()
    while True:
        if not alive():
            log(f"✖ {sid} — the terminal went away")
            return 5
        if (STATE / "answered" / sid).exists():
            settle()
            if check_expr is None or verify(check_expr):
                mark_verified(sid)
                log(f"✓ {sid} done and verified")
                return 0
            log(f"⚠ {sid} — turn ended but the check fails:\n    {check_expr}")
            print("\n".join(pane().splitlines()[-20:]))
            return 3
        screen = pane()
        if answer_question(screen):
            last_change = time.time()
            continue
        rev = hash(screen)
        if rev != last_rev:
            last_rev, last_change = rev, time.time()
        elif time.time() - last_change > stall:
            log(f"✖ {sid} — no screen change for {stall // 60} min")
            return 1
        time.sleep(5)


def mark_verified(sid: str) -> None:
    (STATE / "verified").mkdir(exist_ok=True)
    (STATE / "verified" / sid).write_text(str(time.time()))


def drop_files(stage: dict) -> None:
    inbox = WORK / "inbox"
    inbox.mkdir(exist_ok=True)
    for rel in stage.get("drop", []):
        src = DEMO / rel
        shutil.copy2(src, inbox / src.name)
        log(f"  inbox ← {src.name}")


# --------------------------------------------------------------------------- run
def sent_ids() -> set[str]:
    p = STATE / "markers.jsonl"
    return {json.loads(line)["id"] for line in p.read_text().splitlines()} if p.exists() else set()


def cmd_run(a: argparse.Namespace) -> int:
    if not alive():
        log("no session; run `drive.py start` first")
        return 5
    while True:
        # Re-read the plan every chapter: chapters can be inserted mid-run.
        stages = tomllib.loads(STAGES.read_text())["stage"]
        ids = [s["id"] for s in stages]
        first = ids.index(a.start) if a.start in ids else 0  # --from: skip earlier chapters
        st = next((s for s in stages[first:] if not (STATE / "verified" / s["id"]).exists()), None)
        if st is None:
            break
        sid = st["id"]
        if (STATE / "answered" / sid).exists() or sid in sent_ids():
            # Sent earlier (driver restarted mid-chapter): wait, never send twice.
            log(f"↻ {sid} already sent — waiting on it")
        else:
            drop_files(st)
            settle()
            jsonl_append(
                STATE / "markers.jsonl", {"t": time.time(), "id": sid, "kind": "stage", "label": f"{sid} {st['name']}"}
            )
            log(f"▶ {sid} {st['name']}: {st['prompt']}")
            send(st["prompt"])
        rc = wait_turn(sid, st.get("verify"))
        if rc:
            return rc
        if a.until and sid == a.until:
            return 0
    log("✓ all chapters done")
    return 0


def cmd_say(a: argparse.Namespace) -> int:
    n = len((STATE / "said.jsonl").read_text().splitlines()) if (STATE / "said.jsonl").exists() else 0
    sid = f"say{n + 1:02d}"
    jsonl_append(STATE / "said.jsonl", {"id": sid, "text": a.text, "after": a.after})
    jsonl_append(
        STATE / "markers.jsonl",
        {"t": time.time(), "id": sid, "kind": "say", "label": f"補充：{a.text[:24]}", "after": a.after},
    )
    log(f"▶ {sid}: {a.text}")
    send(a.text)
    return wait_turn(sid, None)


def cmd_finish(_: argparse.Namespace) -> int:
    settle(5, 120)
    jsonl_append(STATE / "session.jsonl", {"t": time.time(), "event": "finish"})
    # Stop asciinema first: the cast ends on Claude Code's live screen, never on
    # the alt-screen teardown that /exit would print.
    subprocess.run(["pkill", "-INT", "-f", f"asciinema rec .*{RAW.name}"])
    time.sleep(3)
    tmux("kill-session", "-t", SOCK)
    log(f"■ recording closed: {RAW}")
    return 0


def cmd_status(_: argparse.Namespace) -> int:
    for st in CFG["stage"]:
        done = (STATE / "answered" / st["id"]).exists()
        ok = done and verify(st.get("verify") or "true")
        print(f"{st['id']} {'✓' if ok else ('…' if done else ' ')} {st['name']}")
    print("session:", "alive" if alive() else "none")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("start")
    r = sub.add_parser("run")
    r.add_argument("--from", dest="start")
    r.add_argument("--until")
    s = sub.add_parser("say")
    s.add_argument("text")
    s.add_argument("--after", default=None, help="stage id this message belongs to")
    sub.add_parser("finish")
    sub.add_parser("status")
    a = ap.parse_args()
    return {"start": cmd_start, "run": cmd_run, "say": cmd_say, "finish": cmd_finish, "status": cmd_status}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
