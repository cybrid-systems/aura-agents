# Iteration-speed KPI (#30)

`lib/project/kpi.aura` collects the inner-loop metrics, labels every
number as a measurement or a target, and compares the Aura loop with a
generic edit-file/headless-run loop on the same tank arena workload.
Speed numbers from CI are never mixed into `wall_ms_per_inner_round`.

## Metrics

- `candidates_per_minute`: candidates judged per minute of inner-loop
  wall time.
- `wall_ms_per_inner_round`: one mutate/fork/rehearse/judge round.
- `time_to_first_playable_ms`: from the benchmark start (including spec
  compile on the Aura side) to the first successful move rehearsal.
- `time_per_milestone`: cumulative wall time when each phase first
  passes. The current benchmark uses representative phase scripts, not a
  full playthrough; it is labelled as a phase benchmark.
- `inner_to_outer_ratio`: inner rounds divided by recorded outer PRs.
- `avg_n`, `early_stop`, `oom_degraded`, `hot_swap_failures`.

`kpi:summary` returns `targets`, `labels` (`measured`/`not-measured`/
`target`) and `status` (`meets-target`/`below-target`/`not-measured`).
`kpi:compare` returns speedup and candidate ratios; if the two sides do
not share inception semantics, `first_playable_ratio` is
`not-comparable` rather than a fake ratio. `kpi:report-action` returns
a `comment-issue` action for `aura#5405`.

## Reproduce

```
AURA_BIN=/path/to/aura KPI_ROUNDS=10 KPI_CANDIDATES=4 \
  bash scripts/kpi-compare.sh
```

- Aura side: `scripts/kpi_inner.aura` runs four representative phases
  through `loop:rehearse-bounded` with four candidates per round.
- Generic side: `scripts/kpi_generic.py` writes a fresh Aura source file
  per candidate and launches a new headless Aura process; this is a local
  headless baseline, not GitHub Actions. CI/container wall time is
  reported separately and excluded from the inner-loop metric.
- Outputs land in `out/kpi/kpi-{aura,generic,compare}.json`.

## First measured run

Host: 14 CPU / 44,135 MiB, arm64 (not the 8-core/16 GiB target profile;
the actual hardware is recorded in the JSON). Same host both sides.

- Aura inner loop: 4 ms/round, 56,470 candidates/min, 40 rounds,
  first playable 25 ms; phase cumulative move/fight/levels/fun
  25/71/117/166 ms.
- Generic local headless: 54 ms/round, 4,413 candidates/min,
  first playable 15 ms; phase cumulative move/fight/levels/fun
  15/567/1164/1692 ms.
- Measured ratios: 13.5x wall per round, 12.8x candidates/min. First
  playable is **not comparable**: the Aura side includes spec/inception
  work, the generic side starts from an existing project. These are
  measurements, not promises; the target statuses are in the JSON.

## Aura side on the v0.3.4 nightly

Host: 12 CPU / 29.3 GiB, aarch64; Aura nightly `cb7d55e7d`; Aura side
only (`scripts/kpi_inner.aura`, three runs each), before and after the
self-target run in `docs/perf.md`:

- candidates/min 53 333 / 53 631 / 53 333 -> 79 338 / 72 727 / 81 355;
- wall of the 40 rounds 179 / 180 / 180 ms -> 118 / 121 / 132 ms, so
  4 -> 2-3 ms/round at the clock's resolution;
- first playable 15 / 16 / 16 ms -> 14 / 14 / 15 ms; phase cumulative
  move/fight/levels/fun 16/65/113/166 ms -> 14/52/84/119 ms (one run
  each, the third).

The gain is one native hash copy per arena frame instead of five and
one call per numeric field read. The generic side was not re-run; the
ratio against it is not restated here.

## Tests

`tests/kpi_test.aura` pins the aggregation, target/label/status output,
comparison winner and the not-comparable rule with synthetic metrics.
