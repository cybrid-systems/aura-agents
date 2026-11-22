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
