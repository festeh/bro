#!/usr/bin/env bash
set -euo pipefail
sleep 1
exec livekit-server --dev --redis-host localhost:6379
