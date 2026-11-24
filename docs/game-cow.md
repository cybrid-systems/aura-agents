# Live COW and hot replace (#29)

`lib/game/cow.aura` is the thin adapter over Aura's live-workspace
primitives. The caller must first create and evaluate a workspace with
`set-code` + `eval-current`; a plain file or `-e` top-level has no
workspace and `mutate :snapshot` returns `-1`.

- `cow:snapshot` / `cow:restore` — named workspace snapshot and rollback.
- `cow:overlay-begin` / `overlay-set!` / `overlay-get` / `overlay-commit` /
  `overlay-rollback` — one COW overlay per fiber; private writes until
  commit, losers roll back.
- `cow:rebind` — replace one define's body without `eval-current`, so
  tick, entity and RNG state stay live.

`scripts/cow-live-check.sh` runs `scripts/fixtures/cow_live.aura` and
asserts:

- a workspace snapshot id is available;
- an overlay sees 11 and the root stays 0 after rollback;
- two ticks reach 2, a hot rebind changes the next tick to +10, and the
  counter reaches 12 without resetting;
- two fibers each see their own overlay value (21/22) and the root stays 0.

CI runs the same check. The pure game loop still deep-copies game state;
this adapter covers the live workspace COW/hot-replace half.
