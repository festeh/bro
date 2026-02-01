#!/usr/bin/env bash
set -euo pipefail
docker rm -f bro-redis 2>/dev/null || true
exec docker run --rm --name bro-redis -p 6379:6379 redis:7 redis-server --bind 0.0.0.0
