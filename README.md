# aura-agents

Planner, worker, and judge prompts plus supervisor policy for unattended multi-agent delivery over the Aura bus ([aura#5398](https://github.com/cybrid-systems/aura/issues/5398), target [aura-redis#15](https://github.com/cybrid-systems/aura-redis/issues/15)).

The bus, the task board, capabilities, and the `aura agent` runner live in [cybrid-systems/aura](https://github.com/cybrid-systems/aura). This repo is the product workflow: prompts, role orchestration, how many workers fit on this machine, and a demo.

## Install

Install the Aura nightly (the same prebuilt release CI uses):

```bash
export PATH="$(bash scripts/install-aura.sh):$PATH"
aura --version
```

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
