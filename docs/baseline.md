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

## Installer contract

The nightly tag is rebuilt in place: the archive under a fixed asset name
is replaced, so the digest the baseline pins can name a build the release
no longer publishes. Every member repo's `scripts/install-aura.sh`
therefore:

- verifies the download against the digest the release publishes beside
  the archive (`<asset>.sha256`), not against the pinned digest, so an
  unverified binary is never installed;
- keys its cache by that digest, so a rolled nightly replaces the cached
  binary instead of leaving an arbitrarily old one in place;
- reports a stale pin on stderr, and fails the install under
  `AURA_REQUIRE_PINNED=1` for the caller that gates on the pinned build
  (the nightly pin job holds the last green pin instead of testing a
  newer build in the pinned one's place).

The pinned digest stays the coordination record: `check-baseline.py`
still fails when the repos disagree, and moving the pin is the pin
workflow's job.

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

Each payload names the target repo, `orchestra/baseline-<sha9>` branch,
and a profile: `aura-project` (patch the `[dependencies]` keys in the
repo's own `aura.toml`, never replace the file), `aura-source` (write
`AURA_REF`), `submodule` (move the `third_party/aura` pointer), or
`baseline-gate` (baseline + gate only). Every payload also carries the
baseline file, the `install-aura.sh` / `check-baseline.py` assets, a
workflow digest patch, a rollback pointer, and
`force-push/admin-merge/tag/release` in `forbidden_actions`.

## Rollout

The generator and aura-agents gate are live. The cross-repo bump branches
`orchestra/baseline-<sha9>` carry the same Aura commit, nightly archive
digests and `aura-ci` digest into `aura-perf`, `aura-harness`,
`aura-memory`, `aura-memory-runtime`, `aura-runner` and `aura-redis`.
Each branch is a normal reviewed PR; a failed target CI is a real
compatibility signal, not something the generator hides.

aura-agents is pinned at `cb7d55e7d` (v0.3.4); `bump-baseline.py --check`
prints the member and stage payloads for that commit, and they were not
pushed with the aura-agents pin.
