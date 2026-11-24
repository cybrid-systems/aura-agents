# Project inception (#21)

One line in, a verifiable game spec plus the fixed four-level ladder out.
The module is pure data: it never creates a repository, never writes to
GitHub and never asks the human a clarifying question.

## Compile

```
(project:compile "用 aura 写一个坦克大战游戏")
;; => (ok spec)
```

The spec carries `genre`, `view`, `style`, `players`, `controls`,
`input_devices`, `entities`, `collision_rules`, `win_conditions`,
`lose_conditions`, `levels`, `seed`, `entry`, `rules`, `assertions`,
`milestones`, `defaults`, `audit`, `overrides` and a deterministic
`fingerprint`. Compiling the same sentence twice yields the same
fingerprint.

## Written defaults

`(project:defaults)` is the table the conductor uses when the sentence
is silent. Every entry is copied into `spec.audit` as
`default-applied`; an explicit constraint becomes
`default-overridden` and records the reason. The operator never has to
answer a question to start a green-field project.

Current defaults include: one player, classic Battle City rules,
top-down view, four-direction movement, destructible brick,
indestructible steel, impassable water, a base, enemies from the top,
a fixed 16 ms tick, a 50 ms tick budget, two levels, seed 42,
1280x720 and keyboard input.

## Extend

```
(project:extend spec "要双人")
```

Extension recompiles the source plus the new sentence. Non-conflicting
defaults keep their values; the new constraint only changes its own
key. `players` becomes 2, a second control scheme and the
`player-two-controls` assertion appear, and the original defaults remain
in the audit.

For a `#25` requirement added to a live project, use
`requirements:extend` instead: it keeps the passed ladder, freezes the
old assertions as a regression suite, inserts the new `duo` milestone
and emits a new contract fingerprint. See `docs/requirements.md`.

## Milestones and assertions

`spec.milestones` is the fixed ladder `move` (能动), `fight` (能打),
`levels` (有关卡), `fun` (好玩), each with its `requires` edge and
assertion ids. `spec.rules` each name at least one assertion from
`spec.assertions`; every assertion is a placeholder for the in-process
frame checks of #23 and says whether it is a state, frame-budget or
visual check.

## Score

```
(project:score spec "move" "mock")
```

Builds the #12 Score for one milestone: the milestone assertion ids are
the contract, the spec fingerprint is attached as `spec_fingerprint`,
and the Score carries a #5403-style budget (`wall_ms`, `tokens`,
`failures`). The Score is ready for the conductor; game-specific
instruments are added by #22/#23, so `score:validate` against the
current target kinds is intentionally not part of this module.
