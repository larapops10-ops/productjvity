#!/bin/sh
# Start the Stage 2-5 API so it survives the terminal session (daemonized, reparented to init).
# Usage: sh apps/api/start.sh [port]
# Stop:  pkill -f "apps/api/server.rb"
cd "$(dirname "$0")/../.." || exit 1
PORT="${1:-3001}"
export PORT
ruby -e 'Process.daemon(true, true); exec("ruby", "apps/api/server.rb")' >/tmp/pjv-api.log 2>&1
sleep 2
curl -s "http://localhost:${PORT}/health" && echo " <- api on ${PORT}"
