#!/usr/bin/env bash
set -euo pipefail

source /usr/local/ifgame/iaf/server/UnityMCP/deploy/common.sh
source "$DEPLOY_DIR/server.env"

# 兜底，避免 crontab/nohup/非登录 shell 丢失动态库路径
export OPENSSL_HOME="${OPENSSL_HOME:-/data/ifgame/server/shared-runtime/openssl-1.1.1w}"
export PY310_HOME="${PY310_HOME:-/data/ifgame/server/shared-runtime/python/python310_ssl11}"
export LD_LIBRARY_PATH="$OPENSSL_HOME/lib:${LD_LIBRARY_PATH:-}"
export PATH="$PY310_HOME/bin:${PATH:-}"

ensure_runtime_dirs

PID="$(read_pid "$MCP_PIDFILE")"
if is_pid_running "$PID"; then
  echo "unity-mcp already running, pid=$PID"
  exit 0
fi

cd "$BASE/Server"

nohup "$BASE/Server/.venv/bin/mcp-for-unity" \
  --transport http \
  --http-host 0.0.0.0 \
  --http-port 10301 \
  --http-remote-hosted \
  --api-key-validation-url "$UNITY_MCP_API_KEY_VALIDATION_URL" \
  --api-key-login-url "$UNITY_MCP_API_KEY_LOGIN_URL" \
  --project-scoped-tools \
  --pidfile "$MCP_PIDFILE" \
  >> "$MCP_LOGFILE" 2>&1 &

if PID="$(wait_for_pidfile "$MCP_PIDFILE" 15)"; then
  echo "unity-mcp started, pid=$PID"
else
  echo "unity-mcp failed to start, check $MCP_LOGFILE"
  tail -n 40 "$MCP_LOGFILE" || true
  exit 1
fi
