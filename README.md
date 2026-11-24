# aura-agents

Planner, worker, and judge prompts plus supervisor policy for unattended multi-agent delivery over the Aura bus ([aura#5398](https://github.com/cybrid-systems/aura/issues/5398), target [aura-redis#15](https://github.com/cybrid-systems/aura-redis/issues/15)).

The bus, the task board, capabilities, and the `aura agent` runner live in [cybrid-systems/aura](https://github.com/cybrid-systems/aura). This repo is the product workflow: prompts, role orchestration, how many workers fit on this machine, and a demo.

## Install

Install the Aura nightly (the same prebuilt release CI uses):

```bash
export PATH="$(bash scripts/install-aura.sh):$PATH"
aura --version
```

## Real aura-redis delivery demo

scripts/demo-redis.sh runs the target fixture from aura#5398 end to end:
one requirement, an approved executable contract, four real bus worker
processes, a task-board audit, and one fast-forward main push.

    export AURA_BIN=/home/dev/aura/build/aura
    export AURA_DEMO_TARGET=/home/dev/aura-redis
    export AURA_DEMO_BASELINE_BIN=/tmp/aura-baseline/aura_redis_server
    export AURA_DEMO_BASELINE_LIB=/tmp/aura-baseline
    bash scripts/demo-redis.sh

The driver starts demo/agents/host.aura, posts four contract-gated tasks
with planner.aura, records the human approval with approver.aura, runs four
worker.aura processes (each claims, executes its task fixture, heartbeats,
reports contract evidence and completes), verifies the board and audit replay
with verify.aura, then builds, tests, compares p99, fast-forwards main and
pushes. The
worker actions are deterministic fixtures (the mock-LLM discipline): the
demo proves the bus workflow, not code synthesis. The shipped fixture uses four tasks; AURA_DEMO_WORKERS may be 4-6
(extra workers drain and exit).

## Quick start

```bash
aura test
AURA_AGENTS_LLM=mock aura run
```

`aura run` reads [demo/requirement.txt](demo/requirement.txt), sizes workers from CPU and memory headroom (no fixed cap), and drives the bus that exists on Aura main today: `bus:host`, `bus:attach`, `bus:subscribe`, `bus:publish`, `bus:query`, `bus:trial`, `bus:keep`, `bus:rollback`, `bus:audit`.

Tests and CI use a deterministic mock LLM and do not open a network connection. A real model goes through `llm:chat`:

```bash
cp .env.example .env   # .env is gitignored; put LLM_API_KEY only there
set -a && . ./.env && set +a
AURA_AGENTS_LLM=real aura run
```

Unset `LLM_MODEL` selects `deepseek-flash` at `https://api.deepseek.com/v1` (DeepSeek V4.1 Flash, the aura-runner preset). `LLM_BASE_URL` and `LLM_MODEL` override that.

## On Aura main today

These calls are the real `std/bus` verbs: host, attach, subscribe, publish, query, trial, keep, rollback, audit.

These are in-process stand-ins, marked in `lib/adapt/`, until the Aura issues land:

| Adapter | Waiting on |
|---|---|
| `task:post-task` / `claim` / `heartbeat` / `complete` / `fail` | [aura#5399](https://github.com/cybrid-systems/aura/issues/5399) |
| `approve:*` | [aura#5404](https://github.com/cybrid-systems/aura/issues/5404) |
| `gate:evidence` | [aura#5391](https://github.com/cybrid-systems/aura/issues/5391), [aura#5402](https://github.com/cybrid-systems/aura/issues/5402) |

Planner and worker peers attach as role 0 until [aura#5400](https://github.com/cybrid-systems/aura/issues/5400) adds those roles and the `aura agent` runner. The demo injects contract approval so the mock smoke can finish; `AURA_AGENTS_APPROVE=timeout` (or `denied`) refuses to start tasks.

The stand-in adapters remain the deterministic default for `aura test`; set `AURA_AGENTS_BUS=real` to probe the kernel's task/approval/gate verbs instead. `lib/graph/ingest.aura` can read a real task timeline with `ingest:from-bus`.

## Orchestra foundation (#11-#13)

`instruments/` declares each section: capability tags, target kinds,
inputs/outputs, required permissions and a cost profile. `lib/instruments/manifest.aura`
validates and loads them; the conductor never hard-codes a section name.
A new section is a manifest plus a peer, no conductor change. Invalid
permissions (keep/rollback on a non-judge) and duplicate names are refused.

`lib/score.aura` is the Score EDSL: requirement + contract fingerprint +
budget + parts with dependency edges. `score:compile` turns one sentence
into a deterministic score through the planner/mock seam; `score:validate`
checks instruments, cycles and budget; `score:to-json`/`from-json` make it
auditable. `lib/conductor.aura` runs the parts in topological order over
the mock sections, journals every transition in `lib/adapt/journal`, and
stops on a contract failure or budget fuse. Its own permission set is
`read,publish` — it never holds `keep`/`rollback` and never writes a target
patch itself.

`baseline/aura-baseline.json` is the orchestra baseline: Aura commit,
nightly archive SHA256 per arch, and the `aura-ci` image digest.
`scripts/check-baseline.py --self` is the drift gate used by CI; it refuses
floating `aura-ci:latest`, a legacy dev image, a missing installer, or a
different commit/digest. The baseline is updated by a reviewed change, never
by a tag or release write.

```bash
aura test
python3 scripts/check-baseline.py --self
```

## Project inception (#21)

`lib/project/spec.aura` turns one green-field sentence such as
`用 aura 写一个坦克大战游戏` into a verifiable Game Spec: entities,
collision rules, win/lose conditions, seeded levels, headless entry and
the fixed four-level ladder `move → fight → levels → fun`. Every rule
names at least one assertion placeholder for the in-process frame checks
of #23. Missing details use the written default table and are recorded
in `spec.audit`; the module never asks a clarifying question. The same
sentence compiles to the same fingerprint, and `project:extend` adds
constraints such as `要双人` without overturning unrelated defaults.
`project:score` emits the #12 Score for one milestone with the spec
fingerprint and a #5403-style budget. Docs: `docs/project-spec.md`.

`lib/project/scaffold.aura` is the #22 dry-run half: from the spec it
returns the repo name, the pinned-baseline `aura.toml` and `aura-ci` CI
workflow, README/.gitignore/game skeleton, the files to copy from this
checkout, branch protection (required `ci`, no direct `main`, no admin
bypass) and the forbidden `tag`/`release`/`large-file` list. It never
creates the repository; the GitHub creator still has to apply it. Docs:
`docs/scaffold.md`.

## Game frame assertions (#23)

`lib/game/assert.aura` evaluates the #21 assertion ids on every frame
inside the rehearsal: movement, collision, fire, brick/steel, water,
enemy spawn/destroy, base loss, clear win, two levels, score/lives,
frame budget, visual keyframe and two-player controls. It takes the
`before -> after` state plus that frame's events and input; no renderer
or filesystem is involved. `game:run` drives a pure `step` function over
an input script and evaluates only the contract ids, returning
`ok/frames/failures` for early stopping. Docs: `docs/game-assert.md`.

`lib/game/arena.aura` is the deterministic 13×13 state machine behind
it: move/block, fire/cooldown, bullet flight, brick vs steel, water,
enemy score, base loss, two levels and clear-win, with no renderer or
external IO. `tests/game_arena_test.aura` runs the real `arena:step`
through the contract for every core rule.

`lib/game/loop.aura` is the N-fiber rehearsal: every candidate gets a
deep-copied root, runs its pure `step` through `game:run`, and the loop
returns per-candidate results plus one winner. `loop:commit` is the hook
for `mutate :rebind`; no candidate writes a file. Docs: `docs/game-loop.md`.

`lib/game/mutate.aura` is the structured candidate generator: a typed
`(tuning ...)` AST with `set`/`add`/`inc`/`remove` ops, canonical source
rendering, read-back round trip and fingerprints. `mutate:arena-opts`
binds a tuning AST into `arena:new` (player speed, fire cooldown, enemy
score); `tests/game_tuning_loop_test.aura` rehearses two ASTs in parallel
and picks the higher-scoring one. No arbitrary source is evaluated.
Docs: `docs/game-mutate.md`.

`lib/game/cow.aura` is the live-workspace adapter: `mutate :snapshot`/
`:restore`, one COW overlay per fiber (`overlay-begin/set!/get/commit`/
`rollback`) and `mutate :rebind` without `eval-current`. The
`scripts/cow-live-check.sh` fixture proves overlay isolation (root stays
0), hot rebind continuity (counter 2 → 12, no reset) and two fibers
seeing 21/22 privately. Docs: `docs/game-cow.md`.

`lib/game/resources.aura` reads `/proc` and chooses N (max 8, one per
CPU, 256 MiB each, never above candidate count); `loop:rehearse-bounded`
runs candidates in capped batches and selects the best winner. Docs:
`docs/game-resources.md`.

The pure game loop still deep-copies game state; the live adapter covers
the workspace COW/hot-replace half. The external PR loop remains open in
#29.

## Experience graph (#2-#9)

`lib/graph/` is a structured, auditable experience graph built in Aura-native code. It never stores model weights, embeddings or source text.

- `schema.aura` — five node types (`keep-evidence`, `rollback-evidence`, `contract-result`, `constraint-rejection`, `pattern`), five deterministic edge types, dual timestamps (`seq` and wall clock), and fail-closed text checks for paths, source and credentials.
- `store.aura` — one graph per workspace under `out/experience/<workspace_id>/` (`snapshot.json` + append-only `events.jsonl`), with replay and idempotent node/edge ids. Workspace A can never read workspace B.
- `ingest.aura` — deterministic projection from the stand-in journal or the real bus audit/task timeline. Zero LLM calls, zero network, idempotent `last_ingested_seq`.
- `query.aura` — bounded (hops, nodes, bytes) read-only path walk for the planner. Invalidated nodes are excluded from the positive set; the hint is appended to `planner:plan-with`.
- `invalidate.aura` — worldline rollback / canary revert / constraint change cascades along reverse `depends-on` and `produced-by`, keeps history, and adds `overturned-by` edges.
- `prune.aura` — `std/qd` MAP-Elites elites, constraint-rejection cells, bounded growth, and built-in data-free cold-start seeds.
- `patterns.aura` — fail-closed data-free pattern export/import; a bundle carries no workspace id, path, source, credential or private URL.
- `ab.aura` — deterministic Track A A/B suite (mock LLM) and the `scripts/ab-redis.sh` Track B entry point.

```bash
aura test
AURA_AGENTS_GRAPH=on aura run     # graph=on for the demo pipeline
bash scripts/ab-redis.sh          # Track A now; Track B prints its blocker
```

Set `AURA_AGENTS_GRAPH=on` (or pass `"graph": "on"` to `orchestrate:run`) to seed, ingest, prune and persist the graph after a run. The default is `graph=off`, so the baseline behavior and its goldens are unchanged.

## External load replay (#15)

`lib/replay/replay.aura` is the external load generator: deterministic
RESP corpora with train/`heldout-<token>` separation for aura-redis, and
a headless newline-JSON session for aura-runner (`hello` -> ticks ->
`wish`) with `first_wish_ms`, tick p50/p99 and over-budget percentage.
`instruments/load-replay.json` declares the section with
`read`+`network` only. `aura test` covers corpus/framing/metrics;
`bash scripts/replay-smoke.sh` drives both real TCP fixtures. Docs:
`docs/replay.md`.

## Harness chief judge (#16)

`lib/harness/judge.aura` runs the four gates as one verdict:
structure (protected symbols, taxonomy, compression floor), solution/harm
(shortcut TTL/retry, hardcoded answer, train-up/held-out-down, dual-thin),
anti-cheat (forbidden prefixes, protected config, contract fingerprint) and
held-out evidence (ok Perf, heldout replay token, numeric heldout score).
The positive candidate returns a complete `keep` package; every negative
case returns `rollback` with reasons. Only the judge's keep verdict asks
for `keep,rollback`; normal permissions are `read,publish`.
Docs: `docs/harness.md`; tests: `tests/harness_test.aura`.

## Memory curator (#17)

`lib/memory/curator.aura` is the bridge to the experience graph, not a
second store. It classifies provenance (kept/rejected/lost-conflict/
lost-pinned/decayed/replaced), projects Harness keep/rollback and audit
outcomes through the existing event ingest, serves the bounded #5
`EXPERIENCE GRAPH` hint (including `AVOID` lines), and triggers #6
worldline invalidation. Each workspace stays in its own
`out/experience/<id>/`; `memory:use-backend! "cxx"` is refused until the
stage-2 runtime exposes an Aura binding and concurrency.
Docs: `docs/memory.md`; tests: `tests/memory_test.aura`.

## Unattended PR pipeline (#18)

`lib/pipeline/pipeline.aura` is the policy half of the delivery pipeline:
standard `orchestra/<task>` PR with Score/Perf/Harness evidence, a merge
gate that only returns `auto-merge` for protected/green/reviewed PRs, and
post-merge cleanup. It hard-refuses `force-push`, `--admin`, direct
main, tags and releases; high-risk paths need an explicit approval.
Canary compares p99/error/functional and returns a standard revert PR on
regression. Rate, in-flight, cooldown, budget and kill-switch guards are
policy state. Docs: `docs/pipeline.md`; tests: `tests/pipeline_test.aura`.

## Resident season (#19)

`lib/troupe/troupe.aura` is the aura-runner loop: external replay metrics
detect a probe-free motif (tick p99, first-wish, over-budget), a small Score
is composed, candidates are pre-filtered by rehearsal, the Harness judge
gates them, and the pipeline delivers/merges with a canary + revert path.
Harmful candidates stop at the judge; rate limits and kill switch stop at
the PR plan. Docs: `docs/troupe.md`; tests: `tests/troupe_test.aura`.

## Baseline bump generator (#13)

`scripts/bump-baseline.py --check` compares the locked Aura commit,
nightly archive digests and `aura-ci` digest with the rolling release.
`--simulate --sha ... --ci-digest ...` emits the next baseline plus the 7
member/stage Bump PR payloads (aura.toml, baseline file, workflow digest
patch, rollback pointer, forbidden actions) without network or any
tag/release write. `--self-test` is wired into CI. Docs:
`docs/baseline.md`; drift gate: `scripts/check-baseline.py --self`.
