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

Real example from this workstation after the tools were installed:

```
mode=proc-stat-only  paranoid=3
missing=[]
blocked=[{tool:perf, reason:perf_event_paranoid=3 ...},
         {tool:bpftrace, reason:root-required}]
usable={perf:#f, bpftrace:#f, ss:#t, proc:#t}
```

`perf:profile-plan` therefore returns `perf-blocked` (not a fabricated
plan) and the report names the missing capability.

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

`(perf:offcpu-plan-with tools pid seconds)` chooses
`offcputime-bpfcc` when bpftrace is present and
`perf sched record` otherwise; with neither it is
`offcpu-unavailable`, never a fabricated stack.
`(perf:flamegraph-plan-with tools)` returns the on-CPU and off-CPU
flamegraph pipelines (`stackcollapse-perf.pl` + `flamegraph.pl`).

## Live external evidence

`scripts/live-acceptance.sh` starts a real `aura-redis` and a real
headless `aura-runner`, drives both over their normal protocols, then
prints `perf-mode`, `perf-blocked`, `perf-cpu-util`, `perf-ss`,
`perf-tcp`, `perf-hypotheses` and the full `perf-json`. Targets are not
modified; the script owns all load.

Point it at local checkouts:

```bash
AURA_BIN=/path/to/aura \
AURA_REDIS_BIN=/path/to/aura_redis_server \
AURA_RUNNER_DIR=/path/to/aura-runner \
bash scripts/live-acceptance.sh
```

## Evidence-only peer

`(perf:evidence)` wraps the report as a `perf-evidence` hash with
`mode`, `degraded`, `missing_probes` and `caps` = `read,publish`.
The Perf section has no `keep`/`rollback` path and never writes a target
branch.
