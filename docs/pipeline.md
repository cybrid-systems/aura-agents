# Unattended PR pipeline (#18)

`lib/pipeline/pipeline.aura` is the policy half of the delivery pipeline.
It returns actions and payloads; it never calls GitHub and never touches a
tag or release.

## Flow

1. `pipeline:plan-pr` requires `orchestra/<task-id>`, a score, issue,
   Perf evidence (`ok:true`, degraded flag carried through) and Harness
   evidence (`verdict:keep` + fingerprint). It refuses:
   - `force_push`, `admin_merge`, `direct_main`, `tag`, `release` —
     `*-forbidden`;
   - high-risk paths (`auth/`, `security/`, `protocol/`, `wal/`,
     `.github/`) without explicit `approval` — `approval-required`;
   - rate/inflight/cooldown/budget violations, or a kill switch.
2. `pipeline:merge-gate` requires draft=false, branch protection, all
   checks green, required review, attached evidence and the same Harness
   fingerprint. It only ever returns method `merge`; `admin` and `force`
   are absent/false.
3. `pipeline:post-merge` returns the cleanup steps: delete remote branch,
   verify the main commit, update the issue; no tag/release step exists.
4. `pipeline:canary` compares pre/post p99, error rate and functional
   status. A regression returns `action:revert`; `pipeline:revert-pr`
   builds the standard revert PR payload and records the canary reason for
   the Memory invalidation.

## Guardrails

`pipeline:policy` sets max PRs/day, max in-flight, failure cooldown,
per-repo budget, p99 ratio and error delta. `pipeline:kill!` flips the
global switch; both plan and merge gates then return `kill-switch`.
`pipeline:audit` keeps the state transitions.

## Tests

`tests/pipeline_test.aura` covers the normal open/merge flow, all five
red lines, high-risk approval, missing evidence, rate limit, kill switch,
canary revert/keep and the post-merge steps.
