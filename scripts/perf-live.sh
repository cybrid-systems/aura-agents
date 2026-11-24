#!/usr/bin/env bash
# #14 real external observation: start an unmodified aura-redis and a
# headless aura-runner, record on-CPU samples with perf while the external
# replay drives both, and write report/folded/SVG artifacts plus per-process
# off-CPU runqueue/context-switch counters.
#
# This is deliberately not in CI: it needs perf_event_open permission and
# real target binaries. It fails closed when perf is unavailable.
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
RUNNER_DIR="${AURA_RUNNER_DIR:-$HOME/aura-runner}"
REDIS_BIN="${AURA_REDIS_BIN:-$HOME/aura-redis/native/build/aura_redis_server}"
DURATION="${AURA_PERF_SECONDS:-12}"
REDIS_FREQ="${AURA_PERF_REDIS_FREQ:-499}"
OUT="${AURA_PERF_OUT:-out/perf}"
SUDO_PASS_FILE="${AURA_SUDO_PASS_FILE:-$HOME/keys/sudo}"

mkdir -p "$OUT"
if ! command -v perf >/dev/null 2>&1; then
  echo "perf-live=blocked reason=perf-missing" >&2
  exit 2
fi
if ! perf stat -e task-clock true >/dev/null 2>&1; then
  echo "perf-live=blocked reason=perf-not-usable" >&2
  exit 3
fi
[[ -f "$RUNNER_DIR/core/main.aura" ]] || {
  echo "perf-live: missing aura-runner checkout: $RUNNER_DIR" >&2
  exit 1
}
[[ -x "$REDIS_BIN" ]] || {
  echo "perf-live: missing aura-redis binary: $REDIS_BIN" >&2
  exit 1
}

pick_port() {
  python3 - "$1" <<'PY'
import socket, sys
start = int(sys.argv[1])
for port in range(start, start + 40):
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

listener_pid() {
  ss -ltnp "sport = :$1" 2>/dev/null \
    | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | head -1
}

sudo_run() {
  printf '%s\n' "$(cat "$SUDO_PASS_FILE")" | sudo -S -p '' "$@"
}

redis_port="$(pick_port "${AURA_LIVE_REDIS_PORT:-26499}")"
runner_port="$(pick_port "${AURA_LIVE_RUNNER_PORT:-8908}")"

redis_pid=""
runner_pid=""
stop_pid() {
  [[ -n "${1:-}" ]] || return 0
  kill "$1" 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 0.1
  done
  kill -9 "$1" 2>/dev/null || true
}
cleanup() {
  stop_pid "$runner_pid"
  stop_pid "$redis_pid"
  stop_pid "${runner_job:-}"
  stop_pid "${redis_job:-}"
}
trap cleanup EXIT

echo "perf-live: aura=$AURA_BIN runner=$RUNNER_DIR redis=$REDIS_BIN"
echo "perf-live: redis-port=$redis_port runner-port=$runner_port seconds=$DURATION"

"$REDIS_BIN" --port "$redis_port" --evict lru --maxmemory 120000 \
  >"$OUT/redis.log" 2>&1 &
redis_job=$!
wait_port "$redis_port" 10
redis_pid="$(listener_pid "$redis_port")"

(
  cd "$RUNNER_DIR"
  exec env AURA_WORK="$PWD" LUMEN_LLM_OFF=1 AURA_SANDBOX=off \
    AURA_RUNNER_PORT="$runner_port" \
    "$AURA_BIN" --quiet --preset dev --grant network core/main.aura
) >"$OUT/runner.log" 2>&1 &
runner_job=$!
wait_port "$runner_port" 120
runner_pid="$(listener_pid "$runner_port")"
redis_pid="$(listener_pid "$redis_port")"
[[ -n "$runner_pid" ]] || { echo "perf-live: runner pid not found" >&2; exit 1; }
[[ -n "$redis_pid" ]] || { echo "perf-live: redis pid not found" >&2; exit 1; }
echo "perf-live: runner-pid=$runner_pid redis-pid=$redis_pid"

# Off-CPU floor: runqueue wait + context switches from /proc, no BPF.
python3 scripts/proc_schedstat.py --pid "$runner_pid" --seconds "$DURATION" \
  >"$OUT/runner-offcpu.json" &
offcpu_runner=$!
python3 scripts/proc_schedstat.py --pid "$redis_pid" --seconds "$DURATION" \
  >"$OUT/redis-offcpu.json" &
offcpu_redis=$!

# On-CPU stacks, sampled from outside the target.
perf record -F 99 -g -p "$runner_pid" -o "$OUT/runner-oncpu.data" \
  -- sleep "$DURATION" >"$OUT/runner-perf.log" 2>&1 &
perf_runner=$!
perf record -F "$REDIS_FREQ" -g -p "$redis_pid" -o "$OUT/redis-oncpu.data" \
  -- sleep "$DURATION" >"$OUT/redis-perf.log" 2>&1 &
perf_redis=$!

# Off-CPU stacks need root tracefs/BPF. Record system-wide sched_switch
# and filter both switch-out and switch-in in perf_offcpu.py; a filtered
# record with -p only sees switch-out and cannot close a window.
OFFCPU_STACK=0
perf_sched=""
if [[ -r "$SUDO_PASS_FILE" ]] && sudo_run true >/dev/null 2>&1; then
  sudo_run rm -f "$OUT/offcpu.data" "$OUT/offcpu.data.old" 2>/dev/null || true
  sudo_run perf record -e sched:sched_switch -g -a -o "$OUT/offcpu.data" \
    -- sleep "$DURATION" >"$OUT/offcpu-record.log" 2>&1 &
  perf_sched=$!
  OFFCPU_STACK=1
else
  echo "perf-live: offcpu-stack=blocked reason=sudo-unavailable"
fi

# Give perf record a moment to attach, then drive both real targets with
# a long enough Redis phase to sample it while it is on CPU.
sleep 1
AURA_LIVE_REDIS_PORT="$redis_port" AURA_LIVE_RUNNER_PORT="$runner_port" \
  AURA_LIVE_REDIS_COMMANDS="${AURA_PERF_REDIS_COMMANDS:-50000}" \
  AURA_LIVE_REDIS_HELDOUT_COMMANDS="${AURA_PERF_REDIS_HELDOUT_COMMANDS:-1000}" \
  AURA_SANDBOX=off "$AURA_BIN" --quiet --preset dev --grant network \
  scripts/fixtures/live_acceptance.aura >"$OUT/live-acceptance.txt" 2>&1

wait "$perf_runner"
wait "$perf_redis"
wait "$offcpu_runner"
wait "$offcpu_redis"
if [[ -n "$perf_sched" ]]; then
  if ! wait "$perf_sched"; then
    OFFCPU_STACK=0
    echo "perf-live: offcpu-stack=blocked reason=sched-record-failed"
  fi
fi

for target in runner redis; do
  perf report -i "$OUT/$target-oncpu.data" --stdio --no-children \
    >"$OUT/$target-report.txt" 2>"$OUT/$target-report.err"
  perf script -i "$OUT/$target-oncpu.data" \
    >"$OUT/$target-oncpu.script" 2>"$OUT/$target-script.err"
  python3 scripts/perf_flamegraph.py \
    --script "$OUT/$target-oncpu.script" \
    --folded "$OUT/$target-oncpu.folded" \
    --svg "$OUT/$target-oncpu.svg" \
    --title "aura-$target on-CPU"
done

if [[ "$OFFCPU_STACK" == 1 ]]; then
  for target in runner redis; do
    pid_var="${target}_pid"
    if ! sudo_run perf script -i "$OUT/offcpu.data" 2>/dev/null \
      | python3 scripts/perf_offcpu.py --script - --pid "${!pid_var}" \
          --folded "$OUT/$target-offcpu.folded" \
          --svg "$OUT/$target-offcpu.svg" \
          --drop-unknown \
          --title "aura-$target off-CPU"; then
      echo "perf-live: offcpu-stack=blocked target=$target"
      OFFCPU_STACK=0
    fi
  done
  if [[ "$OFFCPU_STACK" == 1 ]]; then
    echo "perf-live: offcpu-stack=ok"
  fi
  sudo_run chown "$(id -u):$(id -g)" "$OUT/offcpu.data" 2>/dev/null || true
else
  echo "perf-live: offcpu-stack=blocked"
fi

AURA_PERF_RUNNER_REPORT="$OUT/runner-report.txt" \
AURA_PERF_REDIS_REPORT="$OUT/redis-report.txt" \
AURA_SANDBOX=off "$AURA_BIN" --quiet --preset dev \
  scripts/fixtures/perf_report.aura >"$OUT/report.txt" 2>&1

sed -n 's/^perf-evidence-json=//p' "$OUT/report.txt" >"$OUT/live-evidence.json"
for marker in perf-mode= perf-blocked= runner-top-count= redis-top-count= \
  perf-hypotheses=; do
  grep -q "^${marker}" "$OUT/report.txt" || {
    echo "perf-live: missing report marker $marker" >&2
    tail -n 30 "$OUT/report.txt" >&2
    exit 1
  }
done

echo "perf-live: artifacts=$OUT"
echo "perf-live: runner $(sed -n 's/^runner-hot=//p' "$OUT/report.txt") $(sed -n 's/^runner-hot-pct=//p' "$OUT/report.txt")%"
echo "perf-live: redis  $(sed -n 's/^redis-hot=//p' "$OUT/report.txt") $(sed -n 's/^redis-hot-pct=//p' "$OUT/report.txt")%"
echo "perf-live: offcpu-runner=$(cat "$OUT/runner-offcpu.json")"
echo "perf-live: offcpu-redis=$(cat "$OUT/redis-offcpu.json")"
cleanup
trap - EXIT
echo "perf-live=ok"
