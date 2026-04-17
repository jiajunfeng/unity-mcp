#!/usr/bin/env bash

BASE=/usr/local/ifgame/iaf/server/UnityMCP
DEPLOY_DIR=$BASE/deploy
RUN_DIR=$BASE/run
LOG_DIR=$BASE/logs
RUNTIME_DIR=$BASE/runtime

AUTH_PIDFILE=$RUN_DIR/auth.pid
MCP_PIDFILE=$RUN_DIR/unity-mcp.pid
AUTH_LOGFILE=$LOG_DIR/auth.out
MCP_LOGFILE=$LOG_DIR/mcp.out

read_pid() {
  local pidfile="$1"
  if [[ -f "$pidfile" ]]; then
    cat "$pidfile" 2>/dev/null || true
  fi
}

is_pid_running() {
  local pid="$1"
  [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null
}

ensure_runtime_dirs() {
  mkdir -p "$RUN_DIR" "$LOG_DIR" "$RUNTIME_DIR"
}

ensure_log_dirs() {
  mkdir -p "$RUN_DIR" "$LOG_DIR"
}

print_pid_status() {
  local name="$1"
  local pidfile="$2"
  if [[ -f "$pidfile" ]]; then
    local pid
    pid="$(read_pid "$pidfile")"
    if is_pid_running "$pid"; then
      echo "running pid=$pid"
    else
      echo "stale pidfile"
    fi
  else
    echo "not running"
  fi
}

wait_for_pidfile() {
  local pidfile="$1"
  local timeout_s="$2"
  local pid=""
  local i
  for i in $(seq 1 "$timeout_s"); do
    sleep 1
    if [[ -f "$pidfile" ]]; then
      pid="$(read_pid "$pidfile")"
      if is_pid_running "$pid"; then
        echo "$pid"
        return 0
      fi
    fi
  done
  return 1
}

stop_pidfile_process() {
  local name="$1"
  local pidfile="$2"
  local graceful_wait="$3"

  if [[ ! -f "$pidfile" ]]; then
    echo "$name not running"
    return 0
  fi

  local pid
  pid="$(read_pid "$pidfile")"
  if is_pid_running "$pid"; then
    kill "$pid"
    sleep "$graceful_wait"
    if is_pid_running "$pid"; then
      kill -9 "$pid"
    fi
  fi

  rm -f "$pidfile"
  echo "$name stopped"
}
