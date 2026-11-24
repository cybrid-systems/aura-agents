# In-process rehearsal loop (#24/#29)

`lib/game/loop.aura` runs N candidate step functions against one root
state in N fibers. Each candidate gets a full deep copy of the root, so a
candidate cannot write through the shared state. The loop never writes a
file; the caller decides whether to commit the winner.

```
(loop:rehearse root candidates inputs ids)
;; => {ok, winner, results, state}
```

A candidate is `{id, step}` and may also carry its own `root` state;
`loop:run-one` deep-copies that root instead of the shared one. This is
how tuning ASTs become different candidates. `results` keeps per-candidate `ok`,
`frames`, `failures`, `score` and final `state`. The score prefers a
candidate that satisfies the contract, then its game score; a failing
candidate gets a negative score from its failure count. The best result
wins, ties keep the earlier candidate.

`loop:commit` accepts the winner result and a commit function. The
function receives the winning state, which is the hook a live process
would use for `mutate :rebind` / hot replacement. The actual
`mutate :snapshot`/`:restore` hot swap is #29's remaining live-process
work; this module owns the deterministic rehearsal and selection.

`tests/game_loop_test.aura` proves two fibers start from the same root,
the normal candidate moves to x=5, the frozen candidate stays at x=4,
the root stays at x=4, the winner is selected, and `loop:commit`
receives the winning state. No candidate writes a file.
