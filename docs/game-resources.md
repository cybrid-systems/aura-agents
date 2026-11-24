# Resource-adaptive rehearsal width (#29)

`lib/game/resources.aura` reads `/proc/cpuinfo` and `/proc/meminfo` and
chooses a safe N for the in-process rehearsal:

- CPU count from `processor` lines (fallback 1);
- `MemTotal` in MiB (fallback 0);
- `resources:choose-n-for cpus mem candidates`: at most 8, one candidate
  per CPU, 256 MiB per candidate, never above the candidate count, at
  least 1.

`loop:rehearse-bounded root candidates inputs ids max-n` runs candidates
in batches of at most `max-n`, collects each batch's winner, and picks the
best overall. The result keeps the normal `ok/winner/results/state` shape
plus `batches`. This caps parallel memory/CPU while preserving the same
contract checks and winner selection.

`tests/game_resources_test.aura` pins the choices (8/4/4/1/2), checks the
live snapshot is readable, and runs three candidates in two batches with
the first-pass winner selected. No OOM path is exercised on the test box;
the cap is the guard.
