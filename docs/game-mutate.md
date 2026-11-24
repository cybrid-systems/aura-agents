# Structured tuning AST (#28)

`lib/game/mutate.aura` is the candidate generator for the rehearsal loop.
It models tuning as a small typed AST, not as free source text:

```
(tuning (bullet-speed 1) (enemy-score 100)
        (fire-cooldown 3) (player-speed 1))
```

`mutate:new` creates the default AST. `mutate:apply` accepts structured
ops (`set`, `add`, `inc`, `remove`) and returns a new AST; the original
is untouched. `mutate:candidates` turns an op list into candidate rows
with `id`, `op`, `ast`, canonical `source` and `fingerprint`.

`mutate:to-source` renders the canonical sorted form and
`mutate:from-source` reads it back with `read-from-string`; the round
trip preserves the fingerprint. Invalid non-`tuning` source returns
`(error bad-tuning)`. The module never evaluates arbitrary source, never
writes a file and never touches a target branch.

`tests/game_mutate_test.aura` covers default source, set/inc/remove/add,
round-trip fidelity, three generated candidates and rejection of a
non-tuning form. Binding the parsed AST into a live game step is the
#24/#29 adapter work; this module owns the structured mutation and
AST-to-source fidelity.
