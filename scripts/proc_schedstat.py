#!/usr/bin/env python3
"""Sample /proc/<pid>/task/*/schedstat and status over a window.

This is the external off-CPU floor when tracefs/BPF are not available:
runqueue wait time and voluntary/involuntary context switches per task.
It is not a stack sampler and does not claim to be one.
"""
from __future__ import annotations

import argparse
import glob
import json
import time


def read_window(pid: int) -> dict[str, int]:
    run_ns = wait_ns = slices = 0
    vol = invol = 0
    for path in glob.glob(f"/proc/{pid}/task/*/schedstat"):
        try:
            parts = open(path, encoding="ascii").read().split()
            if len(parts) >= 3:
                run_ns += int(parts[0])
                wait_ns += int(parts[1])
                slices += int(parts[2])
        except (OSError, ValueError):
            continue
    for path in glob.glob(f"/proc/{pid}/task/*/status"):
        try:
            for line in open(path, encoding="ascii"):
                if line.startswith("voluntary_ctxt_switches:"):
                    vol += int(line.split()[1])
                elif line.startswith("nonvoluntary_ctxt_switches:"):
                    invol += int(line.split()[1])
        except (OSError, ValueError):
            continue
    return {
        "run_ns": run_ns,
        "wait_ns": wait_ns,
        "slices": slices,
        "voluntary_ctxt_switches": vol,
        "nonvoluntary_ctxt_switches": invol,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--seconds", type=float, default=10.0)
    args = parser.parse_args()
    before = read_window(args.pid)
    time.sleep(args.seconds)
    after = read_window(args.pid)
    delta = {k: max(0, after[k] - before[k]) for k in before}
    print(json.dumps({
        "pid": args.pid,
        "seconds": args.seconds,
        "run_ms": round(delta["run_ns"] / 1e6, 3),
        "wait_ms": round(delta["wait_ns"] / 1e6, 3),
        "slices": delta["slices"],
        "voluntary_ctxt_switches": delta["voluntary_ctxt_switches"],
        "nonvoluntary_ctxt_switches": delta["nonvoluntary_ctxt_switches"],
        "source": "external-only:/proc/PID/task/*/schedstat,status",
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
