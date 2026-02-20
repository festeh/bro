#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/share/mise/shims:$PATH"
source .env
export PYTHONPATH="$PWD"
exec uv run python agent/main.py dev
