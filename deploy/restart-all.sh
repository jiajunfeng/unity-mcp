#!/usr/bin/env bash
set -euo pipefail

source /usr/local/ifgame/iaf/server/UnityMCP/deploy/common.sh

"$DEPLOY_DIR/stop-all.sh"
sleep 2
"$DEPLOY_DIR/start-all.sh"
