#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .env

sleep 2
mkdir -p recordings
chmod 777 recordings
exec docker run --rm --network host \
    -e EGRESS_CONFIG_BODY="log_level: debug
api_key: ${LIVEKIT_API_KEY}
api_secret: ${LIVEKIT_API_SECRET}
ws_url: ws://localhost:7880
insecure: true
redis:
  address: localhost:6379" \
    -v "$(pwd)/recordings:/out" \
    livekit/egress:latest
