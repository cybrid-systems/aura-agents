# Graduation reflux (#35)

`lib/project/reflux.aura` exports only data-free patterns from a
graduation report into the #2 experience graph, through the #17 curator.

## Payload

`reflux:extract` takes a whitelist, never free text:

- `mode` (`graduation`)
- `rounds`
- `pr_count`
- `seed_version`
- `failure_modes` (only known labels)
- `operator_credit`
- `sentinel_incidents`
- `recipe`
- `gate = "required"`

The summary is `graduated skill: N unattended rounds`. Unknown values such
as a report's `notes` or `risks` are not copied.

## Privacy gate

`reflux:check` recursively refuses:

- paths (`/`), URLs (`://`);
- credentials (`API_KEY`, `SECRET`, `PASSWORD`, `TOKEN=`, `ghp_`, `AKIA`,
  `sk-`);
- user text (`customer`, `client`, `conversation`, `user-text`,
  `transcript`, `prompt`).

A refusal is returned with `reason = "unsafe-text"`; the payload is not
silently rewritten. `reflux:push` writes only after this check passes and
`memory:pattern!` accepts the node (the graph's own privacy gate runs
again).

## Retrieval

`reflux:hint` is the read-only planner path: it returns the bounded
`memory:hint` plus `gate-required = #t` and the backend name
(`aura-native`). A promoted pattern is a candidate input, not a KEEP.

## Evidence

`tests/reflux_test.aura` builds a report with a customer note, extracts a
clean pattern, pushes it, and checks the node is a `pattern` with
`worldline = 0` and no customer text. It also refuses a customer summary,
a URL and a credential in the extracted payload, and confirms the node
count does not grow on refusal.
