#!/usr/bin/env bash
set -euo pipefail

source /usr/local/ifgame/iaf/server/UnityMCP/deploy/common.sh

echo "== auth =="
print_pid_status "auth" "$AUTH_PIDFILE"
curl -fsS http://127.0.0.1:10302/health || true
echo

echo "== unity-mcp =="
print_pid_status "unity-mcp" "$MCP_PIDFILE"
curl -fsS http://127.0.0.1:10301/health || true
echo
