# Termination, budget and Aura-defect intake (#26)

`lib/project/lifecycle.aura` is the policy layer above the #24 milestone
state. It never creates an issue, PR, tag or release; it returns the
action an adapter may execute.

## Definition of Done

```
(lifecycle:done? ms lc)
```

A project is Done only when all of these hold:

- every ladder stage is `passed`;
- `milestone:verify` accepts the audit chain;
- there is no inflight PR;
- every passed stage's `passed_round` is a real round with `ok`, `assertions_ok`
  and a #16 `keep` verdict;
- the budget is not frozen and the Kill Switch is off.

Otherwise the result lists reasons such as `ladder-incomplete`,
`audit-invalid`, `inflight-pr`, `contract-failure`, `budget:*` or
`kill-switch`.

## Termination report

```
(lifecycle:report ms lc (hash "unadopted" ... "aura_issues" ...))
```

The report is a `termination-report` with `reason` (done, in-progress,
budget, kill-switch, failures, aura-defect), the ladder status with
round/worldline/PR/commit per stage, merged PRs, policy/used/remaining
budget, unadopted requirements, Aura issue links and
`release: {tag: #f, release: #f}`. Done never means release.
`lifecycle:report-action report` turns it into a `comment-issue` action
for `cybrid-systems/aura#5405` (JSON body, no tag/release).

## Budget and fail-closed dispatch

`lifecycle:policy` caps wall time, tokens, failures and PR count both
project-wide and per stage. `lifecycle:spend` and `lifecycle:fail!`
increment the counters and freeze the project when a cap is reached.
The freeze reason is `budget:wall_ms`, `budget:tokens`,
`budget:failures` or `budget:prs`.

`lifecycle:dispatch` locks out `patch`, `merge` and `pr` actions once
frozen or killed; `create-repo` remains allowed, matching the #26 rule
that the Kill Switch stops everything except creating the green-field
repository. `lifecycle:merge-gate` is the same check for auto-merge.

## Aura defect intake

`lifecycle:aura-defect` accepts kinds `compiler`, `runtime`, `stdlib`
or `toolchain`, computes a deterministic fingerprint from kind, version,
summary and repro, and searches the supplied existing issues first. A
hit returns `action: existing` and the issue number.

A new defect returns `action: create-issue` for `cybrid-systems/aura`
with a Chinese title/body, `language: zh`, and:
`allowed_actions: create-issue, link-issue, record-evidence`;
`forbidden_actions: fix-pr, kernel-patch, tag, release`; and
`fix_pr: #f`, `kernel_patch: #f`. No kernel fix or PR is ever proposed.

`lifecycle:defect-decision` records the project's response:
`workaround`, `degrade` or `terminate`. It also fixes
`fix_pr: #f`; `terminate` sets `terminate_project: #t` and reason
`aura-defect` for the termination report.
`lifecycle:record-defect!` appends the decision to the lifecycle audit
so the workaround/degrade/terminate choice is replayable.

## Tests

`tests/lifecycle_test.aura` covers a four-stage Done report (with no
tag/release), an incomplete ladder, failure/wall-time budget freezes,
fail-closed dispatch while `create-repo` stays open, Kill Switch
dispatch and report, and the defect dedupe/create/decision matrix
including the forbidden kernel-fix actions.
