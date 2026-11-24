#!/usr/bin/env bash
# One deterministic worker task for the aura-redis demo.
# Usage: agent-task.sh <ref>
# Requires AURA_DEMO_TARGET (target checkout) and AURA_DEMO_PATCH_DIR.
set -euo pipefail

REF="${1:?task ref}"
TARGET="${AURA_DEMO_TARGET:?AURA_DEMO_TARGET is required}"
PATCH_DIR="${AURA_DEMO_PATCH_DIR:?AURA_DEMO_PATCH_DIR is required}"
PATCH="$PATCH_DIR/$REF.patch"

[[ -f "$PATCH" ]] || { echo "missing patch: $PATCH" >&2; exit 2; }
cd "$TARGET"

if git apply --check "$PATCH" 2>/dev/null; then
  git apply "$PATCH"
elif git apply --reverse --check "$PATCH" 2>/dev/null; then
  echo "task $REF: patch already applied"
else
  echo "task $REF: patch does not apply" >&2
  exit 3
fi

case "$REF" in
  1)
    ./scripts/build-native.sh >/tmp/aura-demo-build.log 2>&1
    python3 - <<'PY'
import socket, subprocess, sys, time
from pathlib import Path
ROOT = Path.cwd()
sys.path.insert(0, str(ROOT / "tests"))
from smoke_client import redis_call
port = 28911
proc = subprocess.Popen(
    [str(ROOT / "native/build/aura_redis_server"), "--port", str(port)],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    time.sleep(0.3)
    s = socket.create_connection(("127.0.0.1", port), 2)
    assert redis_call(s, "ZADD", "z", "1", "a", "2", "b", "3", "c") == 3
    assert redis_call(s, "ZRANGEBYSCORE", "z", "(1", "3") == ["b", "c"]
    assert redis_call(s, "ZRANGEBYSCORE", "z", "1", "(3") == ["a", "b"]
    assert redis_call(s, "ZRANGEBYSCORE", "z", "(1", "(3") == ["b"]
    assert redis_call(s, "ZRANGEBYSCORE", "z", "2", "(2") == []
finally:
    proc.terminate()
    proc.wait(timeout=3)
print("task 1: exclusive bounds pass")
PY
    ;;
  2)
    python3 -m py_compile tests/test_prod_zset.py
    python3 - <<'PY'
from pathlib import Path
text = Path("tests/test_prod_zset.py").read_text()
assert '"ZRANGEBYSCORE", "z", "(2"' in text
print("task 2: compatibility test compiles and covers exclusive bounds")
PY
    ;;
  3)
    python3 -m py_compile scripts/bench_zset_p99.py
    python3 scripts/bench_zset_p99.py --help >/dev/null
    echo "task 3: p99 benchmark compiles"
    ;;
  4)
    grep -q 'exclusive bounds' docs/commands.md
    echo "task 4: command contract updated"
    ;;
  *)
    echo "unknown task ref: $REF" >&2
    exit 4
    ;;
esac

