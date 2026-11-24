# Perf section (#14)

The Perf section observes a target from the outside. It never adds a
probe, a metrics endpoint or a sampling hook to the target repository.

## Capability tiers

`perf:probe` checks the host before any collection:

| tier | requires |
|---|---|
| `full-ebpf` | usable `perf`, usable `bpftrace`, readable `/proc`, `perf_event_paranoid <= 1` |
| `perf-only` | usable `perf`, readable `/proc`, `perf_event_paranoid <= 2` |
| `proc-stat-only` | readable `/proc` (USE from `/proc`, `ss` when usable) |
| `minimal` | neither |

Installed is not usable. The probe runs `perf stat -e task-clock true`,
`bpftrace -e 'BEGIN { exit(); }'` and `ss -s`; a tool that is present but
refuses becomes:

- `missing`: not installed;
- `blocked`: installed but refused, with a reason
  (`perf_event_paranoid=3 ...`, `root-required`, ...);
- `usable`: the booleans the tier is computed from.

A contract that requires stronger evidence is refused by
`(perf:require-evidence mode "ebpf")` with `capability-missing`; it is
never silently skipped or reported as green.

Real example from this workstation after `perf_event_paranoid=1`:

```
mode=perf-only  paranoid=1
missing=[]
blocked=[{tool:bpftrace, reason:root-required}]
usable={perf:#t, bpftrace:#f, ss:#t, proc:#t}
```

On-CPU `perf record` works; stack-level off-CPU still needs BPF/tracefs.
`perf:profile-plan` returns `perf-blocked` only when perf itself is not
usable (never a fabricated plan).

## USE snapshot

`perf:report` takes an optional `{"window_ms": n}` hash (default 100)
and reads:

- CPU: two `/proc/stat` samples for utilization, `/proc/pressure/cpu`;
- Memory: `/proc/meminfo`, used percentage;
- Network: `/proc/net/dev` bytes, errors and drops; `/proc/net/snmp` TCP
  retransmits, in-errors and out-RSTs; `ss -s` socket totals/ESTAB/
  TIME_WAIT when usable;
- Disk/IO: `/proc/diskstats` reads, writes, sectors and I/O time for real
  block devices; pseudo devices are skipped.

Network, disk and TCP counts are deltas across the sampling window, not
boot-lifetime totals, so a hypothesis is about this window. `ss` is an
instantaneous snapshot.

Pure parsers are exported for fixtures: `perf:cpu-util`, `perf:mem-used-pct`,
`perf:net-sum`, `perf:pressure`, `perf:ss-summary`, `perf:disk-sum`,
`perf:tcp-snmp`, plus `perf:blocked-probes`. `tests/perf_test.aura` pins
the arithmetic.

`perf:hypotheses` turns the snapshot into evidence-labelled suggestions:
blocked perf/bpftrace, CPU utilization, CPU pressure, memory used,
network errors/retransmits and TIME_WAIT churn. It never claims a cause;
each row carries the observed value. `perf:evidence` includes
`blocked_probes`, `hypotheses` and the full report.

## Profiling plan and attribution

`(perf:profile-plan pid seconds)` returns the `perf record -F 99 -g`
command and the `perf report` command; with `aura#5409` frame pointers
and `/tmp/perf-<pid>.map`, those commands name both C++ and Lisp frames.
If `perf` is absent the plan is `perf-missing` with the current tier.

`(perf:top-symbols report-text [limit])` parses the default
`perf report --stdio --no-children` table into
`overhead_pct` / `command` / `dso` / `symbol` rows. The symbol keeps
spaces (C++ and Lisp names both do).

`(perf:offcpu-plan-with tools pid seconds)` keeps the BPF/`perf sched`
plan surface. When root is available, `scripts/perf-live.sh` uses the
direct tracepoint path instead: `perf record -e sched:sched_switch -g -a`
captures both switch-out and switch-in, and `scripts/perf_offcpu.py`
attributes the window to the stack captured at switch-out. That is a
time-weighted off-CPU flamegraph. `scripts/proc_schedstat.py` remains the
non-root `/proc` floor (runqueue wait + context switches).

`(perf:flamegraph-plan-with tools)` returns the self-contained pipeline:
`perf script` -> `scripts/perf_flamegraph.py` for on-CPU and
`scripts/perf_offcpu.py` for off-CPU -> folded stacks + static SVG. The
CI image has no Perl `flamegraph.pl`, so the Python renderers are the
supported path.

## Live external evidence

`scripts/live-acceptance.sh` starts a real `aura-redis` and a real
headless `aura-runner`, drives both over their normal protocols, then
prints `perf-mode`, `perf-blocked`, `perf-cpu-util`, `perf-ss`,
`perf-tcp`, `perf-hypotheses` and the full `perf-json`. Targets are not
modified; the script owns all load.

`scripts/perf-live.sh` goes one level deeper. While the real targets run:

- `perf record -F 99 -g -p <pid>` samples on-CPU stacks;
- `perf report --stdio --no-children` gives top symbols;
- `perf script` is collapsed by `scripts/perf_flamegraph.py` into folded
  stacks and a static SVG (no Perl flamegraph dependency);
- with root tracefs (`AURA_SUDO_PASS_FILE`, default `$HOME/keys/sudo`),
  `perf record -e sched:sched_switch -g -a` -> `perf_offcpu.py` produces
  the time-weighted off-CPU stacks and SVG;
- `scripts/proc_schedstat.py` samples per-task runqueue wait and
  voluntary/involuntary context switches as the non-root floor.

Artifacts land in `out/perf/`: `*-oncpu.data`, `*-report.txt`,
`*-oncpu.script`, `*-oncpu.folded`, `*-oncpu.svg`, `offcpu.data`,
`*-offcpu.folded`, `*-offcpu.svg`, `*-offcpu.json`,
`live-evidence.json`. The script fails closed when perf or tracefs access
is unavailable; the sudo password file is read only, never written to the
repo.

Real run on this workstation (12 s, 8 concurrent runner clients, 50k
Redis commands):

```
perf-mode=perf-only  blocked=[bpftrace root-required]
runner samples 617: reclaim_tw_unreachable 25-27%, file_reclaim_mark_value ~18%
redis  samples 260: sock_def_readable ~26%, arch_counter_get_cntvct ~7%
runner off-CPU stacks: 76.8 ms, top frames are evaluator / poll paths
redis  off-CPU stacks: 10555 ms, top
  ar_core_serve_forever;serve_once;epoll_pwait ...
  event_base_loop;__poll ...
runner /proc floor: run 5986 ms, runqueue wait 0.25 ms, 202/22 switches
redis  /proc floor: run 543 ms, runqueue wait 1.48 ms, 51012 switches
```

The runner hotspot is the evaluator's value reclamation, not game code;
that is an Aura-runtime finding, not a target patch. The redis off-CPU
flamegraph is dominated by its epoll wait loop, which is the expected
idle-server shape; the runner off-CPU total is tiny because it is mostly
on-CPU.

Point both scripts at local checkouts:

```bash
AURA_BIN=/path/to/aura \
AURA_REDIS_BIN=/path/to/aura_redis_server \
AURA_RUNNER_DIR=/path/to/aura-runner \
AURA_SUDO_PASS_FILE=$HOME/keys/sudo \
bash scripts/live-acceptance.sh
bash scripts/perf-live.sh
```

`AURA_SUDO_PASS_FILE` is optional: without it the script still records
on-CPU and `/proc` off-CPU, and prints `offcpu-stack=blocked` for the
stack-level off-CPU artifacts.

## Evidence-only peer

`(perf:evidence)` wraps the report as a `perf-evidence` hash with
`mode`, `degraded`, `missing_probes` and `caps` = `read,publish`.
The Perf section has no `keep`/`rollback` path and never writes a target
branch.
