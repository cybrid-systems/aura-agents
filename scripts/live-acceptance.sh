#!/usr/bin/env bash
# #15/#14 live acceptance against real targets: a real aura-redis process and
# a real headless aura-runner, driven only over their normal protocols. The
# targets stay unmodified; this script owns every load generator.
set -euo pipefail
cd "$(dirname "$0")/.."

AURA_BIN="${AURA_BIN:-}"
if [[ -z "$AURA_BIN" ]]; then
  if command -v aura >/dev/null 2>&1; then
    AURA_BIN="$(command -v aura)"
  else
    AURA_BIN="$(bash scripts/install-aura.sh)/aura"
  fi
fi
AURA_BIN="$(cd "$(dirname "$AURA_BIN")" && pwd)/$(basename "$AURA_BIN")"

REDIS_BIN="${AURA_REDIS_BIN:-/home/dev/aura-redis/native/build/aura_redis_server}"
RUNNER_DIR="${AURA_RUNNER_DIR:-/home/dev/aura-runner}"
[[ -x "$REDIS_BIN" ]] || { echo "live-acceptance: missing aura-redis binary: $REDIS_BIN" >&2; exit 1; }
[[ -f "$RUNNER_DIR/core/main.aura" ]] || { echo "live-acceptance: missing aura-runner checkout: $RUNNER_DIR" >&2; exit 1; }

pick_port() {
  python3 - "$1" <<'PY'
import socket, sys
start = int(sys.argv[1])
for port in range(start, start + 30):
    s = socket.socket()
    try:
        s.bind(("127.0.0.1", port))
        print(port)
        break
    except OSError:
        continue
    finally:
        s.close()
else:
    raise SystemExit(f"no free port near {start}")
PY
}

wait_port() {
  python3 - "$1" "$2" <<'PY'
import socket, sys, time
port, deadline = int(sys.argv[1]), float(sys.argv[2])
end = time.time() + deadline
while time.time() < end:
    try:
        s = socket.create_connection(("127.0.0.1", port), 0.2)
        s.close()
        raise SystemExit(0)
    except OSError:
        time.sleep(0.1)
raise SystemExit(f"port {port} did not listen in {deadline}s")
PY
}

redis_port="$(pick_port "${AURA_LIVE_REDIS_PORT:-26399}")"
runner_port="$(pick_port "${AURA_LIVE_RUNNER_PORT:-8899}")"
tmp="$(mktemp -d)"
redis_pid=""
runner_pid=""
cleanup() {
  [[ -n "$redis_pid" ]] && kill "$redis_pid" 2>/dev/null || true
  [[ -n "$runner_pid" ]] && kill "$runner_pid" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

echo "live-acceptance: aura=$AURA_BIN"
echo "live-acceptance: redis=$REDIS_BIN port=$redis_port runner=$RUNNER_DIR port=$runner_port"

"$REDIS_BIN" --port "$redis_port" --evict lru --maxmemory 120000 >"$tmp/redis.log" 2>&1 &
redis_pid=$!
wait_port "$redis_port" 10

(
  cd "$RUNNER_DIR"
  export AURA_WORK="$PWD" LUMEN_LLM_OFF=1 AURA_SANDBOX=off
  export AURA_RUNNER_PORT="$runner_port"
  export AURA_EVO_LOG="$PWD/out/evo-acceptance.jsonl"
  "$AURA_BIN" --quiet --preset dev --grant network core/main.aura >"$tmp/runner.log" 2>&1
) &
runner_pid=$!
wait_port "$runner_port" 120

out="$tmp/acceptance.log"
AURA_LIVE_REDIS_PORT="$redis_port" AURA_LIVE_RUNNER_PORT="$runner_port" \
  AURA_SANDBOX=off "$AURA_BIN" --quiet --preset dev --grant network \
  scripts/fixtures/live_acceptance.aura | tee "$out"

for marker in \
  redis-train-ok=#t redis-train-errors=0 redis-train-corpus=train \
  redis-heldout-ok=#t redis-heldout-errors=0 redis-heldout-corpus=heldout \
  runner-ok=#t runner-errors=0 runner-wishes=4 runner-ticks=120; do
  if ! grep -qx "$marker" "$out"; then
    echo "live-acceptance: missing marker $marker" >&2
    echo "--- runner log" >&2
    tail -n 30 "$tmp/runner.log" >&2 || true
    exit 1
  fi
done
for prefix in perf-mode= perf-degraded= perf-blocked= perf-usable= \
  perf-cpu-util= perf-ss= perf-tcp= perf-hypotheses=; do
  if ! grep -q "^${prefix}" "$out"; then
    echo "live-acceptance: missing USE field $prefix" >&2
    tail -n 30 "$out" >&2 || true
    exit 1
  fi
done
for marker in load-ok=8 motif-probe-free=#t motif-score-ok=#t; do
  if ! grep -qx "$marker" "$out"; then
    echo "live-acceptance: missing motif marker $marker" >&2
    tail -n 30 "$out" >&2 || true
    exit 1
  fi
done
echo "live-acceptance=ok"
