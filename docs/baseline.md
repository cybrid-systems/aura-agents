# Orchestra baseline (#13)

`baseline/aura-baseline.json` is the single source for the Aura commit,
nightly archive digests and the `aura-ci` image digest.

## Drift gate

`python3 scripts/check-baseline.py --self` checks:

- `aura.toml` `dependencies.aura_commit`, per-arch `aura_sha256_*`,
  `aura_ci_digest`;
- a pinned `ghcr.io/cybrid-systems/aura-ci@sha256:...` in workflows;
- no floating `aura-ci:latest` or legacy `ghcr.io/cybrid-systems/dev:*`;
- the installer verifies the archive digest.

CI runs it before installing Aura.

## Bump generator

`scripts/bump-baseline.py`:

- `--check` reads the rolling nightly release and the GHCR manifest,
  compares them with the baseline and fails with a payload if they drift;
- `--simulate --sha ... --ci-digest ...` builds the next baseline without
  network access and prints the target Bump PR payloads;
- `--write` updates only the local baseline file (a later reviewed PR
  carries it; the script never writes a tag or release);
- `--self-test` proves the simulated SHA/digest, the 7 member/stage
  payloads, the `aura.toml` replacement, workflow patch, rollback pointer
  and the forbidden-action list.

Each payload contains the target repo, `orchestra/baseline-<sha9>` branch,
`aura.toml` and baseline files, a workflow digest patch, a rollback
pointer, and `force-push/admin-merge/tag/release` in
`forbidden_actions`.

## Remaining rollout

The generator and aura-agents gate are live. Aligning
`aura-perf`, `aura-harness`, `aura-memory`, `aura-memory-runtime`,
`aura-runner` and `aura-redis` to the same digest is the next cross-repo
step; the payloads are ready for review.
