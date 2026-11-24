#!/usr/bin/env python3
"""Turn `perf script` sched_switch events into an off-CPU flamegraph.

Each switch-out of the target pid starts a window; the matching switch-in
closes it. The captured callchain at switch-out is the off-CPU stack, and
the window length is the weight. This is a real stack-level off-CPU view
when tracefs/BPF access is available; it does not touch the target.
"""
from __future__ import annotations

import argparse
import re
import sys
from collections import Counter

try:
    from perf_flamegraph import build_tree, render_svg
except ImportError:  # running from another cwd
    sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
    from perf_flamegraph import build_tree, render_svg


HEADER_RE = re.compile(
    r"^\S+\s+\d+\s+\[\d+\]\s+([0-9.]+):\s+sched:sched_switch:"
    r".*prev_pid=(\d+).*==>\s+\S+\s+next_pid=(\d+)"
)
FRAME_RE = re.compile(r"^\s+[0-9a-fA-F]+\s+(.*?)\s+\(([^)]*)\)\s*$")


def parse(text: str, target: int, drop_unknown: bool = False) -> tuple[Counter[tuple[str, ...]], int]:
    counts: Counter[tuple[str, ...]] = Counter()
    total_us = 0
    pending_start: float | None = None
    pending_stack: list[str] | None = None
    prev_was_out = False
    prev_time: float | None = None
    frames: list[str] = []

    def normalize(raw_frames: list[str]) -> list[str]:
        out = [re.sub(r"\+0x[0-9a-fA-F]+$", "", s).replace(";", ":")
               for s in reversed(raw_frames) if s]
        if drop_unknown:
            out = [f for f in out if f != "[unknown]"]
        return out

    def finalize_previous() -> None:
        nonlocal pending_start, pending_stack
        # The frames collected before this header belong to the previous
        # event. Only that event's callchain may open a target window.
        if prev_was_out and prev_time is not None and pending_start is None:
            pending_start = prev_time
            pending_stack = normalize(frames)

    for raw in text.splitlines():
        header = HEADER_RE.match(raw)
        if header:
            finalize_previous()
            timestamp = float(header.group(1))
            prev_pid = int(header.group(2))
            next_pid = int(header.group(3))
            if next_pid == target and pending_start is not None:
                duration_us = max(1, int(round((timestamp - pending_start) * 1_000_000)))
                if pending_stack:
                    counts[tuple(pending_stack)] += duration_us
                total_us += duration_us
                pending_start = None
                pending_stack = None
            prev_was_out = prev_pid == target
            prev_time = timestamp
            frames = []
            continue
        match = FRAME_RE.match(raw)
        if match:
            frames.append(match.group(1).strip())
    return counts, total_us


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--script", required=True, help="perf script output")
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--folded", required=True)
    parser.add_argument("--svg", required=True)
    parser.add_argument("--title", default="off-CPU")
    parser.add_argument("--width", type=int, default=1200)
    parser.add_argument("--drop-unknown", action="store_true",
                        help="omit [unknown] frames from the rendered stacks")
    args = parser.parse_args(argv)
    try:
        if args.script == "-":
            text = sys.stdin.read()
        else:
            with open(args.script, "r", encoding="utf-8", errors="replace") as handle:
                text = handle.read()
        counts, total_us = parse(text, args.pid, args.drop_unknown)
    except OSError as exc:
        print(f"perf_offcpu: {exc}", file=sys.stderr)
        return 2
    if not counts:
        print("perf_offcpu: no complete off-CPU windows parsed", file=sys.stderr)
        return 3
    with open(args.folded, "w", encoding="utf-8") as handle:
        for stack in sorted(counts):
            handle.write(f"{';'.join(stack)} {counts[stack]}\n")
    render_svg(build_tree(counts), args.svg, args.title, args.width)
    print(f"perf_offcpu: off_cpu_ms={total_us / 1000.0:.3f} stacks={len(counts)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
