#!/usr/bin/env python3
"""Raw recording -> the published cast, with chapters as asciinema markers.

    postprocess.py STATE_DIR OUT_DIR [--idle 2.0]

1. Time zero = the moment the session was ready (session.jsonl "ready"). Startup
   (trust dialogs) is folded into t=0, so playback opens on the ready screen.
2. Chapters: every prompt the driver sent (markers.jsonl) becomes an "m" event,
   placed 0.5 s before the message appears so a seek lands just ahead of it.
3. The end of the take is the last ended turn (turns.jsonl, from the Stop hook)
   plus a few seconds -- the session was never /exit-ed, so the final frame is
   the agent's last answer, not a cleared screen.
4. Idle gaps are capped at --idle seconds (wall-clock -> playback time).
5. Secrets are redacted with same-length markers.

Writes OUT_DIR/demo.cast and OUT_DIR/chapters.json.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import tomllib
from pathlib import Path

TOKEN_SHAPES = [
    r"ghp_[A-Za-z0-9]{20,}",
    r"github_pat_[A-Za-z0-9_]{20,}",
    r"sk-[A-Za-z0-9_-]{20,}",
    r"sk-ant-[A-Za-z0-9_-]{20,}",
    r"AKIA[0-9A-Z]{16}",
    r"xox[abpr]-[A-Za-z0-9-]{10,}",
]


def load_jsonl(p: Path) -> list[dict]:
    return [json.loads(line) for line in p.read_text().splitlines() if line.strip()] if p.exists() else []


def redact(s: str, extra: list[str]) -> str:
    for pat in TOKEN_SHAPES:
        s = re.sub(pat, lambda m: "█" * len(m.group(0)), s)
    for lit in extra:
        if lit and lit in s:
            s = s.replace(lit, "█" * len(lit))
    return s


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("state")
    ap.add_argument("out")
    ap.add_argument("--idle", type=float, default=2.0)
    ap.add_argument("--tail", type=float, default=6.0, help="seconds kept after the last turn ends")
    ap.add_argument("--fast", type=float, default=8.0, help="speed-up while the agent is working")
    ap.add_argument("--head", type=float, default=20.0, help="real-time seconds at the start of each turn")
    ap.add_argument("--foot", type=float, default=15.0, help="real-time seconds at the end of each turn")
    a = ap.parse_args()
    state, out = Path(a.state), Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    stages = tomllib.loads(
        Path(os.environ.get("DEMO_STAGES", Path(__file__).parent.parent / "stages.toml")).read_text()
    )["stage"]
    by_id = {s["id"]: s for s in stages}

    lines = (state / "raw.cast").read_text().splitlines()
    header = json.loads(lines[0])
    events = [json.loads(line) for line in lines[1:] if line.strip()]
    session = {e["event"]: e["t"] for e in load_jsonl(state / "session.jsonl")}
    t_start = session["start"]  # wall clock of cast t=0 (asciinema spawned)
    t_ready = session.get("ready", t_start) - t_start
    # A restarted `start` overwrites raw.cast: only events of the current take count.
    turns = [t for t in load_jsonl(state / "turns.jsonl") if t["t"] >= t_start]
    marks = [m for m in load_jsonl(state / "markers.jsonl") if m["t"] >= t_start]
    said = {d["id"]: d for d in load_jsonl(state / "said.jsonl")}
    t_end = max(t["t"] for t in turns) - t_start + a.tail if turns else events[-1][0]

    # wall-clock (relative) -> playback time, with idle capping
    raw_times = [e[0] for e in events if e[0] <= t_end]
    # Time-lapse: the middle of every turn (agent working) plays at --fast speed;
    # the first --head s (the message going in) and the last --foot s (the
    # answer coming out) stay real time.
    sends = sorted(m["t"] - t_start for m in marks)
    turn_ends = sorted(t["t"] - t_start for t in turns)
    windows = []
    for s0 in sends:
        e = next((e for e in turn_ends if e > s0), None)
        if e and e - s0 > a.head + a.foot:
            windows.append((s0 + a.head, e - a.foot))

    def fast(r: float) -> bool:
        return any(lo <= r < hi for lo, hi in windows)

    def gap(r0: float, r1: float) -> float:
        g = r1 - r0
        if fast(r0) and fast(r1):
            g /= a.fast
        return min(g, a.idle)

    play, prev_raw, prev_play = [], t_ready, 0.0
    for r in raw_times:
        if r > t_ready:
            prev_play += gap(prev_raw, r)
            prev_raw = r
        play.append(prev_play)

    def to_play(r: float) -> float:
        """Map a raw time to playback time (between events: capped gap)."""
        if r <= t_ready:
            return 0.0
        best_raw, best_play = t_ready, 0.0
        for rr, pp in zip(raw_times, play, strict=True):
            if rr > r:
                break
            best_raw, best_play = rr, pp
        return best_play + gap(best_raw, r)

    extra = [os.environ.get("REDACT", "")]
    out_events = []
    # events after the end of the take have no playback time: zip stops there
    for (_, kind, data), p in zip(events, play, strict=False):
        out_events.append([round(p, 6), kind, redact(data, extra)])

    chapters = []
    for m in marks:
        p = max(0.0, to_play(m["t"] - t_start) - 0.5)
        if m["kind"] == "stage":
            st = by_id[m["id"]]
            label = f"{st['id']} {st['name']}"
            chapters.append(
                {
                    "id": st["id"],
                    "part": st["part"],
                    "name": st["name"],
                    "prompt": st["prompt"],
                    "kind": "stage",
                    "t": round(p, 3),
                }
            )
        else:
            d = said.get(m["id"], {})
            label = "補充"
            chapters.append(
                {
                    "id": m["id"],
                    "part": "",
                    "name": "補充",
                    "prompt": d.get("text", ""),
                    "kind": "say",
                    "after": d.get("after"),
                    "t": round(p, 3),
                }
            )
        out_events.append([round(p, 6), "m", label])

    # turn ends -> chapter end times (for the rail's durations)
    ends = sorted(to_play(t["t"] - t_start) for t in turns)
    for c in chapters:
        later = [e for e in ends if e > c["t"]]
        c["end"] = round(later[0], 3) if later else None

    out_events.sort(key=lambda e: (e[0], e[1] != "o"))
    header = {k: v for k, v in header.items() if k not in ("idle_time_limit",)}
    header["title"] = tomllib.loads((Path(__file__).parent.parent / "stages.toml").read_text())["project"]["title"]
    with (out / "demo.cast").open("w") as f:
        f.write(json.dumps(header, ensure_ascii=False) + "\n")
        for e in out_events:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")
    (out / "chapters.json").write_text(json.dumps(chapters, ensure_ascii=False, indent=1))
    (out / "meta.json").write_text(json.dumps({"raw_seconds": round(t_end - t_ready, 1)}))
    total = out_events[-1][0] if out_events else 0
    print(
        f"cast: {len(out_events)} events, {total / 60:.1f} min playback "
        f"(raw {t_end / 60:.1f} min); {len(chapters)} chapters"
    )


if __name__ == "__main__":
    main()
