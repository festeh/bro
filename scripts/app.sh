#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .env

until curl -s http://localhost:8081 >/dev/null 2>&1; do sleep 0.5; done

cd app && exec flutter run -d linux \
    --dart-define=AI_BASE_URL=$AI_BASE_URL \
    --dart-define=AI_API_KEY=$AI_API_KEY
