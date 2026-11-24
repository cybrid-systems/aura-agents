# Game frame assertions (#23)

`lib/game/assert.aura` is the frame-level acceptance core for the
in-process game loop. It evaluates a contract on the state transition
`before -> after` plus the events emitted by that frame. It never reads
the filesystem, the network or a rendered frame.

## State contract

A state is a hash with `player` (`x`, `y`), `tick`, `bullets`, `bricks`,
`steel`, `water`, `enemies`, `score`, `lives`, `level`, `status`,
`frame_ms`, `visual_diff_ok` and `players`. A frame also has an `input`
hash (`move`, `fire`) and a list of events.

## Assertions

`(game:check before after events input id)` covers the #21 ids:

- `move-right`, `move-collision`, `state-advance`
- `fire-bullet`, `bullet-brick`, `bullet-steel`, `enemy-destroy`
- `player-water`, `enemy-spawn`, `base-destroyed-lose`, `clear-enemies-win`
- `two-levels`, `score-lives`, `frame-budget`, `visual-keyframe`,
  `player-two-controls`

Event-driven checks use the frame events (`bullet-hit-brick`,
`bullet-hit-steel`, `blocked-water`, `enemy-spawn`, `enemy-destroy`,
`base-destroyed`, `enemies-cleared`). The frame-budget check uses the
in-process `frame_ms`; a missing perf tool is not involved and cannot be
faked.

## Rehearsal loop

`(game:run init step inputs ids)` runs the inputs through a pure `step`
function, evaluates only the contract ids on each frame, and returns
`{ok, frames, failures, checks, state}`. A failed check stops the
candidate early in the real loop; this module exposes the same result so
#24 can consume it.

`tests/game_assert_test.aura` covers every assertion, a passing move and
fire rehearsal, and a failing fire contract. The actual tank-battle
state machine and COW worldlines are #24/#28/#29; this module is only the
per-frame contract evaluator.
