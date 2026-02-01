#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .env
export PYTHONPATH="$PWD"
exec uv run python agent/voice_agent.py dev
