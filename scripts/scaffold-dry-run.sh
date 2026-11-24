#!/usr/bin/env bash
# #22 dry-run: materialise the generated scaffold in a temp directory and
# prove the placeholder project passes `aura test`. No GitHub API call.
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

DEST="${1:-}"
CLEAN=0
if [[ -z "$DEST" ]]; then
  DEST="$(mktemp -d)"
  CLEAN=1
fi
mkdir -p "$DEST"

plan_file="$(mktemp)"
trap 'rm -f "$plan_file"' EXIT
AURA_SANDBOX=off "$AURA_BIN" --quiet --preset dev scripts/fixtures/scaffold_plan.aura > "$plan_file"
python3 - "$DEST" "$plan_file" <<'PY'
import json, pathlib, shutil, sys

dest = pathlib.Path(sys.argv[1])
line = next(x for x in pathlib.Path(sys.argv[2]).read_text().splitlines() if x.startswith("scaffold-json="))
plan = json.loads(line[len("scaffold-json="):])
for item in plan["files"]:
    path = dest / item["path"]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(item["content"])
for src in plan["copies"]:
    target = dest / src
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, target)
print(f"wrote {len(plan['files'])} files + {len(plan['copies'])} copies to {dest}")
PY

(
  cd "$DEST"
  AURA_SANDBOX=off "$AURA_BIN" test
)

if [[ "$CLEAN" == 1 ]]; then
  rm -rf "$DEST"
fi
echo "scaffold-dry-run=ok"
