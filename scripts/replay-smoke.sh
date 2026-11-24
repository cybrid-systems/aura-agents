#!/usr/bin/env bash
# #15 live replay smoke: a RESP peer and a newline-JSON runner peer.
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

out="$(mktemp)"
trap 'rm -f "$out"; kill $(cat /tmp/replay-redis.pid 2>/dev/null) 2>/dev/null || true; kill $(cat /tmp/replay-runner.pid 2>/dev/null) 2>/dev/null || true' EXIT

AURA_SANDBOX=off AURA_AGENTS_LLM=mock "$AURA_BIN" --quiet scripts/fixtures/replay_live.aura >"$out" 2>&1 || {
  echo "replay live smoke failed" >&2
  cat "$out" >&2
  exit 1
}
cat "$out"
for marker in redis=ok redis-errors=0 heldout-corpus=heldout runner=ok runner-errors=0 wish-positive=#t p99-positive=#t; do
  if ! grep -q "^${marker}$" "$out"; then
    echo "missing marker: $marker" >&2
    exit 1
  fi
done
echo "replay-smoke=ok"
