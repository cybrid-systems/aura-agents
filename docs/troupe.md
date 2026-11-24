# Resident season (#19)

`lib/troupe/troupe.aura` is the aura-runner loop: external metrics ->
motif -> small Score -> rehearsal -> Harness -> guarded delivery -> canary.
It adds no probe to the target.

## Motif

`(troupe:detect baseline current)` compares external replay metrics:
tick p99 > 1.25× baseline (or > 100 ms), first-wish > 2× baseline (or
> 200 ms), and over-budget growth > 20 points. Signals become a `motif`
hash with `probe_free:true`; no signal is `severity:none`.

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

## Tests

`tests/troupe_test.aura` covers the full delivered path, a harmful
candidate blocked by the judge, a canary revert, kill switch guarded and
the clean no-motif path.
