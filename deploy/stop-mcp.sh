#!/usr/bin/env bash
set -euo pipefail

source /usr/local/ifgame/iaf/server/UnityMCP/deploy/common.sh

stop_pidfile_process "unity-mcp" "$MCP_PIDFILE" 2
