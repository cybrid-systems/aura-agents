# Search-strategy wiring (#31)

`lib/game/strategy.aura` connects the real Aura stdlib search stack to
the fork-compete decision points. It does not implement a parallel QD,
MCTS or GA.

## Capabilities (only what exists)

- `std/search`: kinds `grid/pso/abc/fss/ant/es/anneal/bandit/beam/clonal`.
  Used here: `bandit` for operator/arm choice and `beam` for finite edit
  sequences.
- `std/qd`: MAP-Elites archive, insert, coverage, elites, novelty.
- `std/evo-core`: `evo:candidate` and the worldline-isolated
  `evo:trial` handle.
- `std/portfolio`: `successive-halving` budget allocation; rows show
  which members were dropped per round.
- `std/proposer`: present, but not wired for game tuning; deterministic
  `lib/game/mutate` operators are the current proposal source.
- Known gaps, recorded in `strategy:capabilities`: a generic
  stage-aware MCTS (std/search reserves `mcts` and refuses it; only
  `std/proposer` has MCTS-AHD), and a fiber-native early-stop primitive
  (portfolio's halving is the adapter).

## API

```
(strategy:capabilities)                 ; modules/kinds/gaps, missing = ()
(strategy:propose ast n)                ; deterministic mutate candidates
(strategy:rehearse ast root inputs ids n) ; proposals -> loop:rehearse-bounded
(strategy:rehearse-ops ast ops root inputs ids n) ; caller-supplied operators
(strategy:bandit-choose arms scores)    ; std/search bandit -> arm
(strategy:beam-best root tree width scores gens)
(strategy:archive)                      ; std/qd MAP-Elites
(strategy:insert! map cand quality behavior)
(strategy:coverage map) (strategy:elites map)
(strategy:trial genome id evaluate)     ; std/evo-core worldline trial
(strategy:halving members budget-ms)    ; std/portfolio successive halving
```

`strategy:rehearse` turns deterministic proposals into per-candidate arena
roots and runs them through the real `loop:rehearse-bounded`, so candidate
generation is connected to the fork-compete loop, not just a side helper.

`bandit-choose` returns the chosen arm, the arm list and the exported bandit state.
`beam-best` returns the best edit path and score. `halving` returns the
winner, score, round count and all rows; with four members it runs
4+2+1 rows over three rounds.

## Evidence

`tests/strategy_test.aura` exercises every wired surface: ten real
search kinds, deterministic proposal fingerprints, bandit arm choice,
beam edit path, QD insert/replacement/coverage, evo-core trial status
`ok`, and portfolio halving winner/round/row counts. It also asserts the
two known gaps are reported, not silently skipped.

`strategy:capabilities` is the CI-visible gap record: a missing std
require makes the module fail to compile; a capability that exists only
as a reserved name is listed under `gaps`, never as delivered.
