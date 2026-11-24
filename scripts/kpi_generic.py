#!/usr/bin/env python3
"""Generic "edit file + headless run" baseline for #30.

For each candidate we write a fresh Aura source file and launch a new
headless Aura process; this is the per-candidate latency a generic coding
agent pays. It is a local headless baseline, not GitHub Actions: the CI
half is reported separately and never mixed into the inner-loop KPI.
Four representative ladder phases use the same arena scripts as the Aura
side.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
import time
from pathlib import Path

PHASES = [
    {
        "stage": "move",
        "setup": "",
        "inputs": '(list (hash "move" "right"))',
        "ids": '(list "move-right" "state-advance")',
    },
    {
        "stage": "fight",
        "setup": '(hash-set! root "player" (hash "x" 5 "y" 12 "dir" "up"))',
        "inputs": '(list (hash "fire" #t))',
        "ids": '(list "bullet-brick")',
    },
    {
        "stage": "levels",
        "setup": '(hash-set! root "enemies" \'())',
        "inputs": '(list (hash))',
        "ids": '(list "two-levels" "enemy-spawn")',
    },
    {
        "stage": "fun",
        "setup": "",
        "inputs": '(list (hash))',
        "ids": '(list "score-lives" "frame-budget" "visual-keyframe")',
    },
]


def source_for(phase: dict, tag: str) -> str:
    return f"""(require "lib/game/arena")
(require "lib/game/loop")

(define root (arena:new (hash "seed" 42 "players" 1)))
{phase["setup"]}
(define inputs {phase["inputs"]})
(define run
  (loop:rehearse-bounded root
    (list (hash "id" "cand" "step" arena:step))
    inputs
    {phase["ids"]}
    1))
(display "ok=")
(display (hash-ref run "ok"))
(newline)
;; edit {tag}
"""


def hardware() -> dict:
    cpus = os.cpu_count() or 1
    mem_mb = 0
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            if line.startswith("MemTotal:"):
                mem_mb = int(line.split()[1]) // 1024
                break
    except OSError:
        pass
    return {"cpus": cpus, "mem_mb": mem_mb}


def status_lower(value, target):
    if not isinstance(value, (int, float)) or value <= 0:
        return "not-measured"
    return "meets-target" if value <= target else "below-target"


def status_higher(value, target):
    if not isinstance(value, (int, float)):
        return "not-measured"
    return "meets-target" if value >= target else "below-target"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--aura", required=True)
    ap.add_argument("--rounds", type=int, default=10)
    ap.add_argument("--candidates", type=int, default=4)
    args = ap.parse_args()

    repo = Path.cwd()
    started = time.monotonic()
    milestones = {}
    round_walls = []
    total_candidates = 0

    with tempfile.TemporaryDirectory(prefix="kpi-generic-") as tmp:
        tmpdir = Path(tmp)
        for phase in PHASES:
            stage = phase["stage"]
            for r in range(args.rounds):
                started_round = time.monotonic()
                for c in range(args.candidates):
                    path = tmpdir / f"candidate-{stage}-{r}-{c}.aura"
                    path.write_text(source_for(phase, f"{stage}-{r}-{c}"))
                    proc = subprocess.run(
                        [args.aura, str(path)],
                        cwd=repo,
                        text=True,
                        capture_output=True,
                        check=False,
                    )
                    total_candidates += 1
                    if proc.returncode != 0 or "ok=#t" not in proc.stdout:
                        print(proc.stdout)
                        print(proc.stderr, file=os.sys.stderr)
                        raise SystemExit(f"generic candidate {stage}-{r}-{c} failed")
                    if stage not in milestones:
                        milestones[stage] = int((time.monotonic() - started) * 1000)
                round_walls.append(int((time.monotonic() - started_round) * 1000))

    total_wall = sum(round_walls)
    rounds = max(1, len(round_walls))
    wall_per = total_wall // rounds
    cpm = (total_candidates * 60000 // total_wall) if total_wall > 0 else 0
    first_playable = milestones.get("move")
    targets = {
        "wall_ms_per_inner_round": 1000,
        "candidates_per_minute": 60,
        "time_to_first_playable_ms": 60000,
        "inner_to_outer_ratio": 10,
        "hot_swap_failures": 0,
        "oom_degraded": 0,
    }
    summary = {
        "kind": "kpi-summary",
        "label": "generic-edit-file-headless-phases",
        "includes_inception": False,
        "hardware": hardware(),
        "rounds": rounds,
        "candidates": total_candidates,
        "wall_ms": total_wall,
        "wall_ms_per_inner_round": wall_per,
        "candidates_per_minute": cpm,
        "time_to_first_playable_ms": first_playable,
        "time_per_milestone": milestones,
        "inner_to_outer_ratio": 0,
        "avg_n": 1,
        "early_stop": 0,
        "oom_degraded": 0,
        "hot_swap_failures": 0,
        "targets": targets,
        "labels": {
            "wall_ms_per_inner_round": "measured",
            "candidates_per_minute": "measured",
            "time_to_first_playable_ms": "measured" if first_playable is not None else "not-measured",
            "inner_to_outer_ratio": "not-measured",
            "targets": "target",
        },
        "status": {
            "wall_ms_per_inner_round": status_lower(wall_per, targets["wall_ms_per_inner_round"]),
            "candidates_per_minute": status_higher(cpm, targets["candidates_per_minute"]),
            "time_to_first_playable_ms": status_lower(first_playable, targets["time_to_first_playable_ms"]),
            "inner_to_outer_ratio": "not-measured",
            "hot_swap_failures": "meets-target",
            "oom_degraded": "meets-target",
        },
        "note": "local headless subprocess baseline; GitHub Actions/CI wall time is reported separately and excluded from inner-loop metrics",
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
