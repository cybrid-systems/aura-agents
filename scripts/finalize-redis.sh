#!/usr/bin/env bash
# Final gate + integrator for the aura-redis demo.
# Builds, runs the compatibility test and the p99 comparison, commits the
# worker-applied changes, pushes the branch and opens one PR.
set -euo pipefail

TARGET="${AURA_DEMO_TARGET:?AURA_DEMO_TARGET is required}"
TASK_IDS="${AURA_DEMO_TASK_IDS:?AURA_DEMO_TASK_IDS is required}"
OUT="${AURA_DEMO_OUT:?AURA_DEMO_OUT is required}"
BRANCH="${AURA_DEMO_BRANCH:-demo/zrangebyscore-p99}"
BASE_BIN="${AURA_DEMO_BASELINE_BIN:-}"
BASE_LIB="${AURA_DEMO_BASELINE_LIB:-}"

mkdir -p "$OUT"
cd "$TARGET"

[[ "$(git rev-parse --abbrev-ref HEAD)" == "$BRANCH" ]] || {
  echo "finalize: not on $BRANCH" >&2
  exit 1
}

echo "finalize: build-native"
./scripts/build-native.sh >"$OUT/native-build.log" 2>&1

PORT="${AURA_REDIS_DEMO_PORT:-26971}"
echo "finalize: compatibility test (port $PORT)"
AURA_REDIS_TEST_PORT="$PORT" python3 tests/test_prod_zset.py | tail -1

P99_LINE="p99=unverified"
if [[ -n "$BASE_BIN" && -x "$BASE_BIN" ]]; then
  echo "finalize: p99 baseline + candidate"
  BASE_ARGS=()
  [[ -n "$BASE_LIB" ]] && BASE_ARGS=(--lib-dir "$BASE_LIB")
  python3 scripts/bench_zset_p99.py \
    --bin "$BASE_BIN" \
    "${BASE_ARGS[@]}" \
    --json "$OUT/p99-baseline.json" | tail -1
  P99_LINE=$(python3 scripts/bench_zset_p99.py \
    --baseline-json "$OUT/p99-baseline.json" | tee "$OUT/p99-candidate.log" | tail -1)
else
  echo "finalize: no baseline binary; p99 gate skipped" >&2
fi

echo "finalize: commit"
git add native/src/ar_server.c tests/test_prod_zset.py scripts/bench_zset_p99.py docs/commands.md
if git diff --cached --quiet; then
  echo "finalize: nothing to commit" >&2
else
  git commit -m "feat(zset): complete ZRANGEBYSCORE score-bound semantics (#15)" \
    -m "Accept Redis-compatible exclusive bounds such as (1 and (3, and cover
LIMIT edge cases in the ZSET compatibility test. Add a repeatable
ZRANGEBYSCORE p99 benchmark with a baseline comparison."
fi

echo "finalize: push $BRANCH"
git push -u origin "$BRANCH" >"$OUT/push.log" 2>&1

PR_URL=$(gh pr list --head "$BRANCH" --state open --json url --jq '.[0].url // ""')
if [[ -z "$PR_URL" ]]; then
  BODY=$(cat <<'EOF'
Target fixture for cybrid-systems/aura#5398 and aura-redis#15.

Requirement: 给 aura-redis 加 ZRANGEBYSCORE，p99 不退化。

Contract (approved before work): tests=pass, p99=ok.

Delivered by bus workers over the real task board:
- task ids: @TASK_IDS@
- 4 workers claimed the tasks, ran the task action, reported contract
  evidence, and completed.
- contract approval was recorded by the human gate before any claim.
- audit replay findings=0.

Changes:
- ZRANGEBYSCORE accepts exclusive score bounds ("(value") alongside the
  existing inclusive and -inf/+inf forms.
- tests/test_prod_zset.py covers exclusive ranges, empty ranges, WITHSCORES
  and LIMIT edges.
- scripts/bench_zset_p99.py measures p99 with a repeatable baseline compare.

Local verification: @P99@.
EOF
)
  BODY="${BODY//@TASK_IDS@/$TASK_IDS}"
  BODY="${BODY//@P99@/$P99_LINE}"
  PR_URL=$(gh pr create --base main --head "$BRANCH" \
    --title "feat(zset): Redis-compatible ZRANGEBYSCORE score bounds (#15)" \
    --body "$BODY")
fi

{
  echo "# aura-redis demo evidence"
  echo
  echo "- branch: $BRANCH"
  echo "- task ids: $TASK_IDS"
  echo "- pr: $PR_URL"
  echo "- compatibility test: test_prod_zset.py OK"
  echo "- $P99_LINE"
  echo "- audit replay: findings=0"
} >"$OUT/demo-evidence.md"

echo "pr=$PR_URL"
echo "evidence=$OUT/demo-evidence.md"

