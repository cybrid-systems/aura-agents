#!/usr/bin/env python3
"""Combine the Aura and generic #30 summaries into one comparison."""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def ratio(numerator, denominator):
    if not denominator:
        return 0
    return round(numerator / denominator, 2)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("aura")
    ap.add_argument("generic")
    ap.add_argument("output")
    args = ap.parse_args()

    aura = json.loads(Path(args.aura).read_text())
    generic = json.loads(Path(args.generic).read_text())

    aw = aura.get("wall_ms_per_inner_round") or 0
    gw = generic.get("wall_ms_per_inner_round") or 0
    ac = aura.get("candidates_per_minute") or 0
    gc = generic.get("candidates_per_minute") or 0
    af = aura.get("time_to_first_playable_ms") or 0
    gf = generic.get("time_to_first_playable_ms") or 0
    same_inception = bool(aura.get("includes_inception")) == bool(generic.get("includes_inception"))

    comparison = {
        "kind": "kpi-comparison",
        "aura": aura,
        "generic": generic,
        "speedup_wall": ratio(gw, aw),
        "candidates_ratio": ratio(ac, gc),
        "first_playable_ratio": ratio(gf, af) if same_inception else "not-comparable",
        "winner_wall": (
            "aura" if aw and gw and aw < gw else "generic" if aw and gw else "not-measured"
        ),
        "hardware_match": aura.get("hardware") == generic.get("hardware"),
        "labels": {
            "speedup_wall": "measured",
            "candidates_ratio": "measured",
            "first_playable_ratio": "measured" if same_inception else "not-comparable",
            "targets": "target",
        },
        "note": (
            "Measured on the same host. Aura rows are in-process inner-loop "
            "rounds; generic rows are local headless subprocess runs. "
            "GitHub Actions/CI wall time is reported separately and is not "
            "part of wall_ms_per_inner_round."
        ),
    }
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_text(json.dumps(comparison, ensure_ascii=False, indent=2))

    print("# KPI comparison (measured, same host)")
    print()
    print("| metric | Aura inner loop | Generic edit+headless | ratio |")
    print("| :--- | ---: | ---: | ---: |")
    print(f"| wall ms / round | {aw} | {gw} | {comparison['speedup_wall']}x |")
    print(f"| candidates / minute | {ac} | {gc} | {comparison['candidates_ratio']}x |")
    fp_ratio = comparison["first_playable_ratio"]
    fp_label = f"{fp_ratio}x" if isinstance(fp_ratio, (int, float)) else fp_ratio
    print(f"| time to first playable (ms) | {af or 'not-measured'} | {gf or 'not-measured'} | {fp_label} |")
    print()
    print("| phase milestone (ms) | Aura | Generic | note |")
    print("| :--- | ---: | ---: | :--- |")
    for stage in ("move", "fight", "levels", "fun"):
        av = (aura.get("time_per_milestone") or {}).get(stage)
        gv = (generic.get("time_per_milestone") or {}).get(stage)
        note = "same-inception" if same_inception else "not inception-comparable"
        print(f"| {stage} | {av if av is not None else 'not-measured'} | {gv if gv is not None else 'not-measured'} | {note} |")
    print()
    print(f"winner_wall={comparison['winner_wall']}")
    print(f"hardware={json.dumps(aura.get('hardware'), ensure_ascii=False)}")
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
