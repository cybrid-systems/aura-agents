# Bootstrap red lines (#36)

`lib/project/redline.aura` is the testable policy every seeded repository
installs.

## Rules

| Rule | Refusal |
|---|---|
| Sentinel is immutable | `mutate-sentinel`, `edit-sentinel`, protected genome keys/source |
| Ingestion never grants | `ingest-grant` from webhook/message/tool-description/user-paste |
| Merges are revertible | `revert-pr` is allowed |
| No Git bypass | `force-push`, `admin-merge`, `direct-push` |
| No automatic release | `auto-release`; plain `tag`/`release` without `explicit_user` |

A protected merge requires `branch_protected = #t` and
`required_checks = #t`. `redline:audit` returns `ALLOW`/`REFUSE` plus the
policy for the caller's log. It does not itself push, merge, tag or
release.

`redline:guard-genome` refuses protected keys and source mentioning
`game:check`, `harness:judge`, `sentinel:` or the base-destroyed
assertion. `redline:merge` and `redline:release` are the reusable
sub-checks used by #34's handoff.

## Evidence

`tests/redline_test.aura` exercises every refusal, the allowed revert,
protected and force merges, explicit vs automatic release, ingestion with
and without grants, and protected vs safe genomes.
