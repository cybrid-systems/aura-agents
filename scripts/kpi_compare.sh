#!/usr/bin/env bash
# #30 KPI comparison: Aura in-process inner loop vs a generic
# edit-file + headless-run loop on the same tank arena workload.
#
# AURA_BIN must point at an Aura binary. All numbers are measurements;
# the target thresholds live in lib/project/kpi.aura and are labeled
# "target" there. GitHub Actions/CI wall time is not part of the inner
# loop metric.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

aura_bin="${AURA_BIN:-}"
if [[ -z "$aura_bin" ]]; then
  aura_bin="$(command -v aura || true)"
fi
if [[ -z "$aura_bin" ]]; then
  echo "set AURA_BIN to an Aura binary (or install aura on PATH)" >&2
  exit 2
fi

rounds="${KPI_ROUNDS:-10}"
candidates="${KPI_CANDIDATES:-4}"
out="${KPI_OUT:-out/kpi}"
mkdir -p "$out"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

"$aura_bin" scripts/kpi_inner.aura > "$tmp/aura.out"
sed -n 's/^KPI_AURA_JSON=//p' "$tmp/aura.out" > "$out/kpi-aura.json"
if [[ ! -s "$out/kpi-aura.json" ]]; then
  echo "Aura KPI output missing KPI_AURA_JSON" >&2
  cat "$tmp/aura.out" >&2
  exit 1
fi

python3 scripts/kpi_generic.py \
  --aura "$aura_bin" \
  --rounds "$rounds" \
  --candidates "$candidates" > "$out/kpi-generic.json"

python3 scripts/kpi_compare.py \
  "$out/kpi-aura.json" \
  "$out/kpi-generic.json" \
  "$out/kpi-compare.json"
