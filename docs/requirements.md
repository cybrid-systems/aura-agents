# Requirement evolution (#25)

`lib/project/requirements.aura` adds a requirement to a live game spec as
a **new milestone**, not as a rewrite of the ladder that already passed.
It is pure data; it does not write gameplay code or touch GitHub.

## Add a requirement

```
(requirements:extend spec "加上双人模式")
;; => (ok spec') | (error reason)
```

The only supported sentence today is an explicit two-player request
(`双人`). Unspecified behaviour keeps the written default: the single
player mode and its scripts stay. The result:

- `players` becomes 2, a second control scheme is appended, and the
  player entity count becomes 2;
- a new stage `duo` (双人可玩) is inserted after `levels` and before
  `fun`, with assertions `player-two-controls`,
  `player-two-independent-input`, `two-player-shared-level` and
  `solo-regression`;
- the original `move/fight/levels/fun` stages are copied unchanged and
  marked `frozen`; their 14 assertion ids become `spec.regression`;
- `requirements:assertions` supplies the three new placeholder ids; no
  two-player gameplay code is implemented here;
- `revision` increments, `base_fingerprint` records the old contract and
  `fingerprint` is recomputed for the new contract;
- `audit` gains `requirement-added`, `default-overridden:players`,
  `default-applied:single_player_regression` and
  `contract-revised`; `defaults` shows `players=2, default=1` and
  `single_player_regression=#t`;
- `contract_revision` records from/to, requirement and the added
  milestone.

`requirements:regression`, `requirements:audit`,
`requirements:frozen` and `requirements:assertions` expose the revision
without re-parsing source text.

## Attach it to the running ladder

```
(milestone:extend state spec')
```

The state must not have an inflight PR, and `spec'.base_fingerprint`
must equal the state's current `spec_fingerprint`. The extension:

- keeps every passed stage's round, worldline, PR and commit;
- refuses to remove a stage (`stage-removed`) or change any old stage's
  assertion list (`frozen-contract-changed`);
- recomputes the active stage as the first non-passed stage; appending
  the new stage after `levels` in a live project therefore makes `duo`
  active immediately;
- if the new spec would place a new stage before an already-passed
  stage, moves the new stages to the end and reports `reordered=#t`;
- appends a `contract-revised` event to the digest chain and records
  the regression suite and revision on the state.

The new stage then uses the same `milestone:record-round!`,
`milestone:outer-request`, PR and `milestone:land!` path. A duo round
that omits `solo-regression` is rejected with `assertions-uncovered`.

## Tests

`tests/project_requirements_test.aura` covers:

- spec revision ids, fingerprint change, base fingerprint, frozen stages,
  regression membership and the defaults/audit entries;
- solo `move/fight/levels` green, then `加上双人模式`, then `duo`
  active and `fun` queued;
- missing solo regression in a duo round is rejected;
- `duo` then `fun` land and the ladder reaches `done` with five passed
  stages and a valid audit chain;
- a tampered old `levels` contract is rejected with
  `frozen-contract-changed:levels`, and a removed `fun` stage with
  `stage-removed:fun`;
- adding the same requirement twice is rejected, and a non-two-player
  sentence is `unsupported-requirement`;
- a finished project that adds `duo` reports `reordered=#t` and becomes
  active again.
