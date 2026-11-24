# External load replay (#15)

The replay generator lives here, not in the target. It drives a target over
its normal protocol and measures the client-side experience; the target
gets no test mode, hook or endpoint.

## Plan and instrument

`(replay:plan protocol opts)` carries `host`, `port`, `seed`, an optional
`token`, `concurrency`, `duration_s` and `corpus`. The
`instruments/load-replay.json` manifest declares `load.replay` with
`read`+`network` only.

## aura-redis (RESP)

`(replay:redis-corpus seed count token)` builds deterministic
`PING`/`SET`/`GET` commands. A non-empty token prefixes every key with
`heldout-<token>-`; train corpora use `train-`. `(replay:redis-run host
port corpus)` frames each command as RESP, drives a real TCP connection
and returns:

```json
{"ok":true,"kind":"redis-replay","count":12,"errors":0,
 "p50_ms":0,"p95_ms":0,"p99_ms":1,"reconnects":0,"corpus":"train"}
```

## aura-runner (newline JSON)

`(replay:runner-run host port opts)` connects to the runner socket and
sends `hello` -> `tick` (fixed dt, increasing x) -> `wish` at each tick
listed in `wish_ats` (the legacy single `wish_at` still works), reading
state frames. It returns `first_wish_ms`, `wishes`,
`tick_p50_ms`, `tick_p99_ms`, `over_budget_pct` (tick RTT over 50 ms)
and `errors`. The same session can be repeated on a baseline build; the
variance is the held-out input for the Harness judge.

```json
{"ticks":120,"first_wish_ms":6,"wishes":3,"tick_p50_ms":2,
 "tick_p99_ms":17,"over_budget_pct":0.0,"errors":0}
```

## Tests

`aura test` covers the pure corpus/framing/metrics/plan surface
(`tests/replay_test.aura`). The live peers are two small processes:

```sh
AURA_BIN=/path/to/aura bash scripts/replay-smoke.sh
```

It starts `tests/fixtures/redis_fixture.py` and
`tests/fixtures/runner_fixture.py`, drives both over TCP, and checks
`redis=ok`, `heldout-corpus=heldout`, `runner=ok`,
`wish-positive=#t` and `p99-positive=#t`. CI runs the same script. A
real `aura-redis` or `aura-runner` process uses the same calls with its
own host/port.

## Real-target acceptance

`scripts/live-acceptance.sh` is the manual gate for the real processes.
It starts a real `aura_redis_server` and a real headless `aura-runner`
(`LUMEN_LLM_OFF=1`) from sibling checkouts, drives 120 RESP commands
(train and held-out) plus 120 runner ticks with four wishes, and prints
the structured JSON. It also records the `perf:report` USE snapshot; on
a host without `perf`/`bpftrace`/`ss` the probe must say
`proc-stat-only` and `degraded=true`, never fake a green.

```sh
AURA_BIN=/path/to/aura \
AURA_REDIS_BIN=/path/to/aura_redis_server \
AURA_RUNNER_DIR=/path/to/aura-runner \
bash scripts/live-acceptance.sh
```
