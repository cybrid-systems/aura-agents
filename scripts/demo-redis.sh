#!/usr/bin/env bash
# End-to-end demo: a natural-language requirement, an approved contract,
# four real bus worker processes, a task-board audit, and one aura-redis PR.
#
# The worker actions are deterministic fixtures (mock-LLM discipline): the
# demo proves the bus workflow, not code synthesis. Set GH_TOKEN to open the
# PR; local verification and evidence collection do not need it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${AURA_DEMO_TARGET:-/home/dev/aura-redis}"
AURA_BIN="${AURA_BIN:-/home/dev/aura/build/aura}"
WS="${AURA_DEMO_WS:-5398}"
TASKS="${AURA_DEMO_TASKS:-4}"
WORKERS="${AURA_DEMO_WORKERS:-4}"
BRANCH="${AURA_DEMO_BRANCH:-demo/zrangebyscore-p99}"
OUT="${AURA_DEMO_OUT:-$ROOT/out/redis-demo-$(date +%Y%m%d-%H%M%S)}"

[[ -x "$AURA_BIN" ]] || { echo "missing aura binary: $AURA_BIN" >&2; exit 1; }
[[ -d "$TARGET/.git" ]] || { echo "missing target repo: $TARGET" >&2; exit 1; }
[[ -z "$(git -C "$TARGET" status --porcelain)" ]] || {
  echo "target repo is not clean; refusing to discard local changes" >&2
  exit 1
}

mkdir -p "$OUT/run"
chmod 700 "$OUT/run"
export XDG_RUNTIME_DIR="$OUT/run"
export AURA_SANDBOX=off
export AURA_PIPELINE_STRICT=0
export AURA_DEMO_WS="$WS"
export AURA_DEMO_TARGET="$TARGET"
export AURA_DEMO_PATCH_DIR="$ROOT/demo/tasks"
export AURA_DEMO_TASK_SH="$ROOT/scripts/agent-task.sh"
export AURA_DEMO_OUT="$OUT"
export AURA_DEMO_BRANCH="$BRANCH"

HOST_PID=""
exec 3<>/dev/null
cleanup() {
  if [[ -n "$HOST_PID" ]] && kill -0 "$HOST_PID" 2>/dev/null; then
    kill "$HOST_PID" 2>/dev/null || true
    wait "$HOST_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "demo: target=$TARGET workspace=$WS tasks=$TASKS workers=$WORKERS"
git -C "$TARGET" fetch origin >/dev/null 2>&1
git -C "$TARGET" checkout -B "$BRANCH" origin/main >/dev/null

mkfifo "$OUT/host.in"
"$AURA_BIN" "$ROOT/demo/agents/host.aura" <"$OUT/host.in" >"$OUT/host.log" 2>&1 &
HOST_PID=$!
exec 4>"$OUT/host.in"
for _ in $(seq 1 100); do
  grep -q "host-ready" "$OUT/host.log" 2>/dev/null && break
  kill -0 "$HOST_PID" 2>/dev/null || { cat "$OUT/host.log" >&2; exit 1; }
  sleep 0.05
done
grep -q "host-ready" "$OUT/host.log" || { echo "host did not start" >&2; cat "$OUT/host.log" >&2; exit 1; }
echo "demo: host ready (pid $HOST_PID)"

"$AURA_BIN" "$ROOT/demo/agents/planner.aura" | tee "$OUT/planner.log"
TASK_IDS=$(grep -o 'task=[0-9]*' "$OUT/planner.log" | cut -d= -f2 | paste -sd, -)
[[ -n "$TASK_IDS" ]] || { echo "planner produced no task ids" >&2; exit 1; }
echo "demo: contract approval (human gate; sim 1s)"
sleep 1
AURA_DEMO_TASK_IDS="$TASK_IDS" "$AURA_BIN" "$ROOT/demo/agents/approver.aura" | tee "$OUT/approver.log"

echo "demo: launching $WORKERS workers"
WORKER_PIDS=()
for i in $(seq 1 "$WORKERS"); do
  AURA_DEMO_WORKER_ID="w$i" "$AURA_BIN" "$ROOT/demo/agents/worker.aura" >"$OUT/worker-$i.log" 2>&1 &
  WORKER_PIDS+=("$!")
done

FAILED=0
for pid in "${WORKER_PIDS[@]}"; do
  wait "$pid" || FAILED=1
done
cat "$OUT"/worker-*.log
[[ "$FAILED" == 0 ]] || { echo "a worker failed" >&2; exit 1; }

echo "demo: verify task board + audit replay"
AURA_DEMO_TASK_IDS="$TASK_IDS" "$AURA_BIN" "$ROOT/demo/agents/verify.aura" | tee "$OUT/verify.log"
grep -q "verify=PASS" "$OUT/verify.log" || { echo "verify failed" >&2; exit 1; }
grep -q "replay-findings=0" "$OUT/verify.log" || { echo "audit replay not clean" >&2; exit 1; }

echo "demo: final gate + PR"
AURA_DEMO_TASK_IDS="$TASK_IDS" bash "$ROOT/scripts/finalize-redis.sh" | tee "$OUT/finalize.log"

echo quit >&4
exec 4>&-
wait "$HOST_PID" 2>/dev/null || true
HOST_PID=""

echo "demo: done; evidence in $OUT"

