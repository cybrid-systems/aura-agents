# Instruments (#11)

An instrument manifest declares one section's capability, target kinds,
inputs/outputs, permissions and cost. `lib/instruments/manifest.aura`
loads every `instruments/*.json`, validates it, and selects by capability
+ target kind. The conductor reads the registry; it has no hard-coded
instrument names.

Required fields:

| field | meaning |
|---|---|
| `name` | slug, unique in the registry |
| `version` | `major.minor.patch` |
| `bus_role` | 0 generic, 1 perf, 2 harness, 3 maintainer, 4 planner, 5 worker, 6 supervisor (aura#5400) |
| `capabilities` | functional tags from `manifest:known-capabilities` |
| `target_kinds` | exact stage names or `*` |
| `inputs` / `outputs` | evidence or data names |
| `required_caps` | `read`, `publish`, `keep`, `rollback`, `write`, `mutate`, ... |
| `cost` | `wall_ms`, `tokens`, `cpu_pct` (0..100) |

A non-judge instrument may not declare `keep` or `rollback`; validation
returns `unauthorized-verdict`. Duplicate names, unknown capabilities,
bad costs and bad roles are refused.

Add a section by dropping a JSON file here and a peer that consumes its
capability. No conductor source change is needed: `manifest:select` walks
the registry, and `manifest:load-dir` is called at startup. The shipped
`static-check.json` is the extension fixture.
