# Memory curator (#17)

The Memory section is the bridge between the orchestra and the existing
experience graph (#2-#9). It does not implement a second store.

## Provenance

`(memory:provenance outcome)` maps an outcome to the `aura-memory`
state vocabulary:

| outcome | provenance |
|---|---|
| `verdict: keep` | `kept` |
| `verdict: rollback` / `blocked` | `rejected` |
| `kind: lost-conflict` | `lost-conflict` |
| `kind: lost-pinned` | `lost-pinned` |
| `kind: decayed` | `decayed` |
| `kind: replaced` | `replaced` |
| otherwise | `added` |

`(memory:record! graph outcome)` projects a Harness/audit outcome into the
graph's existing event ingest (`gate-keep`, `gate-rollback`,
`constraint-rejection`) with the next logical sequence. It returns the
provenance and the ingest result; node ids and edges remain the #3/#4
store's responsibility.

## Planner hint

`(memory:hint graph requirement)` calls the #5 read-only query and returns
the bounded `EXPERIENCE GRAPH` hint (positive history plus `AVOID`
rollback/rejection lines). `memory:negative?` is true when the hint
carries a negative constraint. The Conductor/Planner can append this hint
to the user turn exactly as `planner:plan-with` already does.

## Invalidation and pruning

`(memory:invalidate! graph worldline seq reason)` calls the #6
worldline-bound invalidation; rollback/canary revert therefore invalidates
every dependent experience without deleting history.
`(memory:prune! graph)` runs #7 with the policy hash
`max-nodes 256 / audit-window 32 / decay-after-seq 4096`.

## Tenant isolation and stage-2 boundary

Each graph is `out/experience/<workspace_id>/`; workspace 9001 cannot
read workspace 9002. `(memory:backend)` is `aura-native`.
`(memory:use-backend! "cxx")` returns `backend-not-available`: the
C++26 `aura-memory-runtime` stays a stage-2 replacement until it exposes
an Aura binding and concurrency, at which point this one function switches
the backing store without changing the graph contract.

## Tests

`tests/memory_test.aura` covers keep/rollback provenance, node types,
planner hint + negative flag, invalidation, tenant isolation, backend
boundary and the provenance vocabulary.
