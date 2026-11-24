# Bootstrap seed (#33)

`lib/project/bootstrap.aura` adds the delivery-time seed to every
green-field scaffold. The seed belongs to the new repository: it runs
without `aura-agents` in the loop, keeps the sentinel frozen, and emits a
guarded PR plan for the repository's own CI.

## Files

`project:scaffold` appends these to the #22 payload:

| File | Role |
|---|---|
| `sentinel/plane.aura` | frozen assertions, protected keys, fingerprint, genome refusal |
| `engine/evolve.aura` | one in-process fork-compete round over fiber rehearsals |
| `bootstrap/run.aura` | one round without the conductor, prints markers |
| `tests/seed_test.aura` + golden | isolation, sentinel, guardrail checks |
| `docs/principles.md` | frozen sentinel, ingest-is-data, revertible merges, no auto release |
| `docs/seed.md` | how to run the seed |

The scaffold manifest (`bootstrap`) reports seed version `1.0.0`, the
protected list, the two CI checks and explicit `tag/release/force/admin =
#f`.

## Round semantics

- One root state is copied per candidate; `fiber:spawn` rehearses them in
  parallel.
- The winner is selected by score; the root keeps its original value.
- The winner is checked by `sentinel:check-genome` before it can produce a
  plan.
- The plan carries branch, title, evidence, one source file, the two
  checks and guardrails (`tag`, `release`, `force`, `admin` all false,
  `branch_protected` true). It does not create a GitHub PR.
- The sentinel fingerprint is stable across the round.

## Verification

`scripts/scaffold-dry-run.sh` materialises the plan into a temporary
repository, runs `aura test` there, then runs `bootstrap/run.aura` and
requires `seed-round=#t`, `winner=c2`, `root-value=0`, the plan branch
and `plan-tag=#f` / `plan-release=#f`. This is the no-conductor path.

`tests/bootstrap_test.aura` checks the plan contents in this repository.
The real create-repo + branch-protection call remains the #22 adapter;
this module only owns the deterministic payload.
