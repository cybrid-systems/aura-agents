# Perf section (#14)

The Perf section observes a target from the outside. It never adds a
probe, a metrics endpoint or a sampling hook to the target repository.

## Capability tiers

`perf:probe` checks the host before any collection:

| tier | requires |
|---|---|
| `full-ebpf` | `perf`, `bpftrace`, readable `/proc`, `perf_event_paranoid <= 1` |
| `perf-only` | `perf`, readable `/proc`, `perf_event_paranoid <= 2` |
| `proc-stat-only` | readable `/proc` (USE from `/proc`, `ss` when present) |
| `minimal` | neither |

The probe reports `degraded=true` and `missing` tool names. A contract
that requires stronger evidence is refused by
`(perf:require-evidence mode "ebpf")` with `capability-missing`; it is
never silently skipped or reported as green.

## USE snapshot

`perf:report` reads:

- CPU: `/proc/stat` (counters), `/proc/pressure/cpu`;
- Memory: `/proc/meminfo`, used percentage;
- Network: `/proc/net/dev` rx/tx bytes, `ss` when available;
- Disk/IO: the same external-only surface; a missing tool is named, not
  synthesized.

Pure parsers are exported for fixtures: `perf:cpu-util` takes two
`/proc/stat` samples, `perf:mem-used-pct` a `meminfo` text,
`perf:net-sum` a `/proc/net/dev` text, and `perf:pressure` a pressure
text. `tests/perf_test.aura` pins the arithmetic.

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

## Evidence-only peer

`(perf:evidence)` wraps the report as a `perf-evidence` hash with
`mode`, `degraded`, `missing_probes` and `caps` = `read,publish`.
The Perf section has no `keep`/`rollback` path and never writes a target
branch.
