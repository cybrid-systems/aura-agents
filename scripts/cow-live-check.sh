#!/usr/bin/env bash
# #29 live check: workspace snapshot, overlay isolation, hot rebind with
# state continuity and two fibers using rollback-only overlays.
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
trap 'rm -f "$out"' EXIT
AURA_SANDBOX=off "$AURA_BIN" --quiet --preset dev scripts/fixtures/cow_live.aura | tee "$out"

for marker in init-tick=0 snapshot=#t overlay-value=11 overlay-root=0 \
  ticks-before=2 rebind=#t ticks-after=12 fiber-1=21 fiber-2=22 \
  root-after-fibers=0; do
  if ! grep -qx "$marker" "$out"; then
    echo "cow-live-check: missing marker $marker" >&2
    exit 1
  fi
done
echo "cow-live-check=ok"
