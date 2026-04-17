#!/usr/bin/env bash
set -euo pipefail

source /usr/local/ifgame/iaf/server/UnityMCP/deploy/common.sh
source "$DEPLOY_DIR/server.env"
source "$DEPLOY_DIR/auth.env"

ensure_log_dirs

PID="$(read_pid "$AUTH_PIDFILE")"
if is_pid_running "$PID"; then
  echo "auth already running, pid=$PID"
  exit 0
fi

nohup "$BASE/Server/.venv/bin/python" "$DEPLOY_DIR/auth_service.py" \
  >> "$AUTH_LOGFILE" 2>&1 &

AUTH_BG_PID=$!
echo "$AUTH_BG_PID" > "$AUTH_PIDFILE"

if PID="$(wait_for_pidfile "$AUTH_PIDFILE" 5)"; then
  echo "auth started, pid=$PID"
else
  echo "auth failed to start, check $AUTH_LOGFILE"
  tail -n 40 "$AUTH_LOGFILE" || true
  exit 1
fi
