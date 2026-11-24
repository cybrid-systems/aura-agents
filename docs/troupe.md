# Resident season (#19)

`lib/troupe/troupe.aura` is the aura-runner loop: external metrics ->
motif -> small Score -> rehearsal -> Harness -> guarded delivery -> canary.
It adds no probe to the target.

## Motif

`(troupe:detect baseline current)` compares external replay metrics:
tick p99 > 1.25× baseline (or > 100 ms), first-wish > 2× baseline (or
> 200 ms), and over-budget growth > 20 points. Signals become a `motif`
hash with `probe_free:true`; no signal is `severity:none`.

`(troupe:detect baseline current perf-hot)` also consumes the real Perf
top-symbol row. A non-idle symbol at ≥20% becomes a `hot-symbol` signal
with the symbol and share attached. The live `aura-runner` run on this
host reports `reclaim_tw_unreachable` at ~25.6% and
`file_reclaim_mark_value` at ~17.7%; that is an Aura-runtime hotspot, so
the motif points at the runtime, not a game patch. `troupe:cycle` reads
the same optional evidence from `cfg.perf`.

## Score and rehearsal

`(troupe:score motif)` builds a small Score (observe -> patch -> static
-> judge -> memory) with the contract `tests=pass, tick-p99=ok`.
`(troupe:rehearse candidates)` keeps only candidates with negative tick
or first-wish delta and no harm; `no-gain` and `harm` are rejected before
any judge/PR work.

## Cycle

`(troupe:cycle cfg)` runs the whole loop:

1. `detect` -> `no-motif` if clean;
2. `score` + `rehearse` -> `no-candidate` if nothing survives;
3. `harness:judge` -> `blocked` on any gate;
4. `pipeline:plan-pr` -> `guarded` on rate/kill/red-line;
5. `pipeline:merge-gate` -> `merge-blocked` if checks/review/evidence fail;
6. `pipeline:canary` -> `delivered` on keep, `reverted` with a standard
   revert PR on regression.

The returned hash keeps motif, rehearsal, judge package, pipeline/merge
actions and canary; the caller can then feed the Memory invalidation and
issue update.

## Live external load

`scripts/live-acceptance.sh` drives a real headless `aura-runner` with
one baseline session (120 ticks, four wishes) and then eight concurrent
external clients (240 ticks, three wishes each). It feeds the observed
p99/first-wish/over-budget values to `troupe:detect` and prints
`motif-severity`, `motif-signals`, `motif-probe-free` and the small
Score. The target is not modified and has no probe.

On the current nightly the target stayed healthy under that load
(`load-p99` ~17 ms, `load-wish` ~6 ms, no over-budget), so the honest
result was `severity:none`. A loaded target that crosses a threshold
emits the same motif shape; the harness does not manufacture one.

## Runtime canary (#5433 / PR #5434)

The live runner's hotspot was in Aura's file-mode reclaim, not in
`aura-runner`; the fix is [aura#5434](https://github.com/cybrid-systems/aura/pull/5434).
The target canary compares the old nightly with that build under the
same 8-client external load:

| run | old p99 | new p99 | old run_ms | new run_ms |
|---|---:|---:|---:|---:|
| 1 | 14 | 8 | 6650 | 4363 |
| 2 | 13 | 8 | 6209 | 4433 |
| 3 | 16 | 10 | 6842 | 5258 |

`first_wish` fell from 7/6/5 ms to 4/5/4 ms; over-budget stayed 0; the
runner's own 32 tests pass on the new binary. `scripts/fixtures/troupe_canary_5433.aura`
runs the existing `troupe:cycle` over these measured values and returns
`delivered` with `pipeline=open-pr`, `merge=auto-merge`, `canary=keep`.
The real merge is the Aura PR, not a fake target patch.

## Tests

`tests/troupe_test.aura` covers the full delivered path, a harmful
candidate blocked by the judge, a canary revert, kill switch guarded and
the clean no-motif path.
