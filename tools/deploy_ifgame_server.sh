#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REMOTE_HOST="${REMOTE_HOST:-ifgame@192.168.1.204}"
REMOTE_BASE="${REMOTE_BASE:-/data/ifgame/server/UnityMCP}"
REMOTE_UV="${REMOTE_UV:-/usr/local/ifgame/.local/bin/uv}"
REMOTE_PYTHON="${REMOTE_PYTHON:-/data/ifgame/server/shared-runtime/python/python310_ssl11/bin/python3.10}"

if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync is required but not found"
  exit 1
fi

if ! command -v ssh >/dev/null 2>&1; then
  echo "ssh is required but not found"
  exit 1
fi

echo "== sync Server/ =="
rsync -rptv \
  --exclude '.venv' \
  --exclude '__pycache__' \
  --exclude '.pytest_cache' \
  --exclude '.mypy_cache' \
  --exclude 'htmlcov' \
  "$ROOT_DIR/Server/" \
  "$REMOTE_HOST:$REMOTE_BASE/Server/"

echo
echo "== sync deploy/ =="
rsync -rptv \
  --exclude 'auth_keys.txt' \
  --exclude 'auth_keys.example.txt' \
  --exclude '*.bak_*' \
  "$ROOT_DIR/deploy/" \
  "$REMOTE_HOST:$REMOTE_BASE/deploy/"

echo
echo "== rebuild remote venv =="
ssh "$REMOTE_HOST" "set -euo pipefail
export OPENSSL_HOME=/data/ifgame/server/shared-runtime/openssl-1.1.1w
export LD_LIBRARY_PATH=\$OPENSSL_HOME/lib:\${LD_LIBRARY_PATH:-}
export UV_PYTHON_DOWNLOADS=never
cd '$REMOTE_BASE/Server'
'$REMOTE_UV' sync --frozen --no-dev --python '$REMOTE_PYTHON'
"

echo
echo "== restart remote services =="
ssh "$REMOTE_HOST" "'$REMOTE_BASE/deploy/restart-all.sh'"

echo
echo "== remote status =="
ssh "$REMOTE_HOST" "'$REMOTE_BASE/deploy/status-all.sh'"
