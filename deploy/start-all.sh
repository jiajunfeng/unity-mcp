#!/usr/bin/env bash
set -euo pipefail

source /usr/local/ifgame/iaf/server/UnityMCP/deploy/common.sh

"$DEPLOY_DIR/start-auth.sh"
"$DEPLOY_DIR/start-mcp.sh"
