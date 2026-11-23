#!/usr/bin/env bash
# Experience-graph A/B entry point (#8).
#
# Track A is deterministic and runs here: mock LLM, graph=off vs graph=on,
# plus an invalidation round. Track B is the real aura-redis#15 target.
# Track B is reported as blocked until the target fixture and the real
# bus verbs (#5399-#5405) are available on the machine. The script never
# invents numbers and never logs LLM_API_KEY.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v aura >/dev/null 2>&1; then
  export PATH="$(bash scripts/install-aura.sh):${PATH}"
fi

export AURA_AGENTS_LLM=mock
unset LLM_API_KEY || true

echo "track=mock"
aura demo/ab.aura

echo "track=real"
if [[ "${AURA_AGENTS_AB_REAL:-0}" != "1" ]]; then
  echo "status=blocked reason=opt-in-required (set AURA_AGENTS_AB_REAL=1, LLM_API_KEY, AURA_REDIS_DIR)"
elif [[ -z "${LLM_API_KEY:-}" ]]; then
  echo "status=blocked reason=LLM_API_KEY-missing"
elif [[ ! -d "${AURA_REDIS_DIR:-}" ]]; then
  echo "status=blocked reason=AURA_REDIS_DIR-missing (cybrid-systems/aura-redis#15 fixture)"
else
  # The target harness is intentionally narrow: it reuses the local
  # aura-redis checkout only as a read-only requirement source. It does
  # not merge, push or modify the target repo.
  export AURA_AGENTS_LLM=real
  echo "target=${AURA_REDIS_DIR}"
  echo "status=ready"
  echo "note=run the same orchestrate pipeline with graph=off and graph=on;"
  echo "note=collect first-pass success, rollback rate, invalidated reuse and p99 CPU time"
  echo "note=aura-redis#15 must be green before the real comparison is meaningful"
fi
