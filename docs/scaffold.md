# Green-field scaffold (#22)

`lib/project/scaffold.aura` is the dry-run half of #22: it turns a #21
Game Spec into the first-day repository payload without creating a
repository, tag or release.

```
(project:scaffold spec)
;; => repo, visibility, files, copies, baseline, branch_protection,
;;    forbidden
```

## What the plan contains

- `repo`: `aura-tank-battle` for the tank-battle spec, `aura-game` otherwise.
- `files`: `aura.toml`, `.github/workflows/ci.yml`, `README.md`,
  `.gitignore`, a placeholder `game/main.aura`, a passing
  `tests/smoke_test.aura` + golden, and the #33 bootstrap seed
  (`sentinel/plane.aura`, `engine/evolve.aura`, `bootstrap/run.aura`,
  `tests/seed_test.aura` + golden, `docs/principles.md`, `docs/seed.md`).
- `bootstrap`: seed version, protected list, seed round/test paths, CI
  checks and explicit `tag/release/force/admin = #f`.
- `copies`: `baseline/aura-baseline.json`, `scripts/install-aura.sh` and
  `scripts/check-baseline.py`, so the new repo starts from the same #13
  single source of truth.
- `baseline`: the exact `aura_commit`, both nightly asset SHA256 values
  and the `aura-ci` digest read from `baseline/aura-baseline.json`.
- `branch_protection`: required `ci`, no direct push to `main`, no admin
  bypass.
- `forbidden`: `tag`, `release`, `large-file`.

`project:scaffold-file` reads one generated file by path for tests or a
future writer. A real creator still has to call the GitHub API, set the
branch protection and push the first scaffold commit; this module only
owns the deterministic payload.

`scripts/scaffold-dry-run.sh` also runs `bootstrap/run.aura` in the
materialised repository and requires a passing seed round, an unchanged
root and a guarded PR plan. This is the #33 no-conductor path.

The #22 acceptance still needs an organisation dry-run repository (or a
production-shaped dry-run API assertion) for the actual create + protect
step. Until then the issue stays open.
