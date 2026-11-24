# Self-evolution meta layer (#32)

`lib/game/meta.aura` wraps `std/evo-meta` around the fork-compete search
from #31. It evolves only *how* the loop searches; it cannot change the
evaluator, the gate, the assertions, the held-out inputs, the contract or
the audit.

## Evolvable and protected

Evolvable keys:

- `propose-prompt`
- `mutation-ops`
- `parent-policy`
- `budget-split`

Protected keys are `std/evo-meta`'s five (`evaluate`, `gate`,
`holdout-split`, `constraints`, `audit`) plus the game sentinel:
`assertions`, `heldout`, `held-out`, `contract`, `sentinel`,
`frame-budget`, `approval`, `sandbox`. `gmeta:guard` refuses a genome
that names one of them or whose source mentions `game:check`,
`base-destroyed-lose`, `frame-budget`, `harness:judge` or `sentinel:`.

The loop is depth 1 and rejects an inner/meta-holdout overlap. The canary
is measured once at construction; a candidate below the baseline is a
`ROLLBACK` and the tip does not move. Approval defaults to auto only in
the test/dry-run path; the gate still owns every KEEP.

## Search wiring

- `gmeta:inner` maps the policy's `mutation-ops` to deterministic
  `lib/game/mutate` operators and calls `strategy:rehearse-ops`, which
  runs the real `loop:rehearse-bounded` over per-candidate arena roots.
- `gmeta:evaluate` returns a rehearsal score (a number), not a hash; the
  outer loop selects on the disjoint meta-holdout task set.
- `gmeta:assertion-hash` is a stable fingerprint of the assertion ids and
  the held-out input script. Promotion never changes it.

## Operator credit and width

- `gmeta:hh` builds a `std/hyper-heuristic` FRRMAB state over the four
  operators.
- `gmeta:credit!` credits a winning arm; `gmeta:next` selects the next
  arm. Warm-start visits every arm once before credit takes over.
- `gmeta:tune-n` derives the rehearsal width from `budget-split`
  (`explore` 0.2 -> 4, 0.9 -> 1) and clamps it to the caller's cap. The
  number is a width, not a speed claim.

## Promotion

`gmeta:promote` writes a data-free recipe to the #2 experience graph
through `memory:pattern!` / the #17 curator. The result is a `pattern`
node with `gate = "required"` and `verdict = "candidate-only"`; the
returned review value still says `gate-required = #t`. A later session can
read it with `gmeta:review` / `memory:hint`, but it must pass the #16 gate
again before a KEEP.

## Evidence

`tests/game_meta_test.aura` checks:

- protected genomes and sentinel source are refused;
- an outer step over real rehearsal audits and leaves the assertion hash
  unchanged;
- a canary drop is `ROLLBACK`, not an applied policy;
- the credited operator is selected after warm-up;
- width follows `budget-split` and the cap;
- a promoted pattern is retrievable from the graph and still
  gate-required.

No wall-clock speed is asserted here. #30 owns measured iteration speed.
