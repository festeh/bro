#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

until curl -s http://localhost:8081 >/dev/null 2>&1; do sleep 0.5; done
just sync-models
cd app && exec flutter run -d linux
