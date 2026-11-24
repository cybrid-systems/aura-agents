#!/usr/bin/env bash
# Mock-LLM demo smoke. Does not call a network LLM.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v aura >/dev/null 2>&1; then
  export PATH="$(bash scripts/install-aura.sh):${PATH}"
fi

export AURA_AGENTS_LLM=mock
export AURA_AGENTS_APPROVE="${AURA_AGENTS_APPROVE:-approved}"
unset LLM_API_KEY || true

out="$(mktemp)"
err="$(mktemp)"
if ! aura run >"$out" 2>"$err"; then
  echo "demo failed" >&2
  cat "$err" "$out" >&2
  exit 1
fi
cat "$out"

need() {
  if ! grep -q "$1" "$out"; then
    echo "missing marker: $1" >&2
    exit 1
  fi
}

need 'demo=ok'
need 'llm=mock'
need 'bus-host=ok'
need 'bus-attach=ok'
need 'bus-trial=ok'
need 'bus-audit=ok'
need 'bus-unhost=ok'
need 'task-backend=stand-in'
need 'approve-backend=stand-in'
if ! grep -E -q 'result=(keep|rollback)' "$out"; then
  echo "missing keep or rollback result" >&2
  exit 1
fi
if grep -q 'http-post' "$out"; then
  echo "mock demo contacted an LLM endpoint" >&2
  exit 1
fi
echo "smoke=ok"

# #12: the Score/Conductor demo must finish on the mock sections.
score_out="$(mktemp)"
if ! aura run demo/score.aura >"$score_out" 2>&1; then
  echo "score demo failed" >&2
  cat "$score_out" >&2
  exit 1
fi
grep -q '^score=done$' "$score_out" || { echo "missing score=done" >&2; exit 1; }
grep -q '^verdict=keep$' "$score_out" || { echo "missing verdict=keep" >&2; exit 1; }
echo "score-smoke=ok"
