# Harness chief judge (#16)

The Harness section is the only judge. It combines four gates into one
verdict package and is the only section that may request `keep`/`rollback`.

## Gates

1. **Structure gate** — rejects protected-symbol edits, a patch with no
   edits, an unknown edit kind, and a deletion above the 30% compression
   floor.
2. **Solution / harm gate** — rejects shortcut patches (zero TTL/retry/
   timeout/max-steps, skipped checks, hardcoded answers, forced flags),
   `train` gains with no `held-out` gain, and a train gain more than
   3× the held-out gain (`dual-thin`).
3. **Anti-cheat guard** — rejects forbidden prefixes (`bus:`, `hbus:`,
   `eval-current`, `set!`, `mutate:rebind`, `current-source`,
   `workspace`, `crypto`, `shell`), a protected-config byte mismatch,
   and a replaced contract fingerprint.
4. **Held-out evidence gate** — requires the `perf` evidence to be ok,
   the replay evidence to be a `heldout` corpus with a non-empty token,
   and a numeric held-out score. Missing evidence fails closed.

`(harness:judge candidate expected)` returns:

```json
{"ok":true,"verdict":"keep","reasons":[],
 "package":{"candidate":"cand-1","fingerprint":"fp-1",
            "gates":{"structure":true,"harm":true,"guard":true,"evidence":true},
            "heldout":{...},"perf":{...},"replay":{...},"verdict":"keep"},
 "package_valid":true,"caps":["keep","rollback"]}
```

A rollback package keeps every gate reason and the evidence that was
present; `harness:package-valid?` checks the package shape. Normal
permissions are `read,publish`; only a keep verdict returns the
`keep,rollback` capability pair.

## Tests

`tests/harness_test.aura` covers the positive baseline and the negative
matrix: protected define, shortcut TTL/retry, hardcoded answer,
train-up/held-out-down, missing Perf evidence, missing replay evidence,
tampered fingerprint, forbidden `set!` patch, and the worker-vs-judge
permission split.
