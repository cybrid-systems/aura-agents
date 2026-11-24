# Milestone state machine (#24)

`lib/project/milestone.aura` advances the four-stage game ladder
(`move` / `fight` / `levels` / `fun`) only when a winner produced by the
live inner loop has landed through the #18 outer loop. It is pure data:
recording a rehearsal round never writes a candidate source file and
never triggers per-candidate CI.

## State

`milestone:new spec opts` takes a #21 `game-spec` and returns a state:

- `stages`: the ladder in spec order, each with its contract assertion
  ids, status (`active` / `pending` / `passed`) and, once passed, the
  round / worldline / PR / commit that proved it;
- `current`: the only stage that may accept new rounds;
- `rounds`: append-only inner-loop records;
- `history`: passed-stage records;
- `inflight`: the single open outer PR, if any;
- `chain`: digest-chained audit events (`inner-round`, `outer-pr`,
  `stage-passed`).

`opts` carries `workspace` (positive integer), `issue` and `repo`.

## Inner loop

`milestone:round-from-runs stage runs harness meta` merges one or more
real `loop:rehearse-bounded` results into one round. This is how a
heterogeneous assertion set is covered honestly: for the `move` stage
one script drives `move-right` / `state-advance`, another drives a
blocked move for `move-collision`. `meta` supplies `id`, `worldline`,
`root_in`, `root_out`, `assertions` and `assertions_ok`.

`milestone:record-round! state round` rejects, in order:

- a round whose stage is not the current active stage;
- missing / zero worldline, candidates or batches;
- `ok` or `assertions_ok` false;
- a #16 verdict other than `keep` or a missing harness fingerprint;
- `files_written` != 0 or `per_candidate_ci` != 0;
- duplicate round id;
- a round whose `assertions` do not cover the stage contract;
- a `root_in` that does not equal the previous same-stage `root_out`
  (hot-replace state continuity).

## Outer loop

`milestone:outer-request state` returns a #18-shaped request plus a
winner evidence pack: winner source, fork tree, N candidates, batches,
early stops, score, worldline, contract assertions, harness package,
inner round count, zero file/CI counters and the audit-chain head. Only
the latest eligible round may be shipped, and only one PR may be
inflight.

`milestone:record-pr! state number url plan` accepts a real
`pipeline:plan-pr` `open-pr` decision and binds its branch, repo, issue
and harness fingerprint to the evidence digest.

`milestone:land! state merge` advances the stage only after a protected
merge with a commit, no force/admin path, a green post-merge assertion
rerun and the same evidence digest. It clears the stage, activates the
next one, records a #2-compatible KEEP outcome (`worldline`,
`candidate_hash`, `contract_hash`, summary) and appends a
`stage-passed` event. The last stage sets `done` and leaves
`current` empty.

## Audit

`milestone:verify state` recomputes every event digest, checks the
prev-digest chain, checks round digests and round references, and
verifies the four ladder statuses. `milestone:audit state` returns the
chain oldest-first. A tampered chain reports `digest-mismatch`; a
tampered round reports `round-digest-mismatch`.

`tests/game_milestone_test.aura` drives a real arena rehearsal, rejects
stage skips / discontinuity / file writes / per-candidate CI / rollback
verdicts, plans and lands PRs for all four stages, feeds the KEEP outcome
into graph workspace 7, and proves the tamper checks.
