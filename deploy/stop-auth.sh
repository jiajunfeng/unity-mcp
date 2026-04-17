#!/usr/bin/env bash
set -euo pipefail

source /usr/local/ifgame/iaf/server/UnityMCP/deploy/common.sh

stop_pidfile_process "auth" "$AUTH_PIDFILE" 1
