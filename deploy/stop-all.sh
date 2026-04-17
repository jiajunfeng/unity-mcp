#!/usr/bin/env bash
set -euo pipefail

source /usr/local/ifgame/iaf/server/UnityMCP/deploy/common.sh

"$DEPLOY_DIR/stop-mcp.sh"
"$DEPLOY_DIR/stop-auth.sh"
