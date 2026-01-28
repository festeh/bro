# Bro - WearOS VAD App

set dotenv-load

wear_avd := "Virtual_Wearable"
phone_avd := "Pixel_8_Pro"

default:
    @just --list

# ─────────────────────────────────────────────────────────────
# Emulator
# ─────────────────────────────────────────────────────────────

# List available AVDs
avds:
    emulator -list-avds

# Start WearOS emulator (workspace 3 via windowrule)
emu-wear:
    emulator -avd {{wear_avd}} 

# Start phone emulator (workspace 3 via windowrule)
emu-phone:
    emulator -avd {{phone_avd}} 

# Kill all emulators
emu-kill:
    adb devices | grep emulator | cut -f1 | xargs -I {} adb -s {} emu kill

# List connected devices
devices:
    adb devices -l

# ─────────────────────────────────────────────────────────────
# Wear
# ─────────────────────────────────────────────────────────────

# Run wear app on emulator (finds first emulator device)
wear:
    #!/usr/bin/env bash
    device=$(adb devices | grep emulator | head -1 | cut -f1)
    if [ -z "$device" ]; then
        echo "No emulator found. Run 'just emu-wear' first."
        exit 1
    fi
    cd wear && flutter run -d "$device"

# Run wear app on real Samsung watch (SM-* device)
wear-device:
    #!/usr/bin/env bash
    device=$(flutter devices 2>/dev/null | grep "SM " | grep -oP '(?<=• )[^ ]+(?= •)' | head -1)
    if [ -z "$device" ]; then
        echo "No Samsung watch found. Connect via Wireless debugging."
        exit 1
    fi
    echo "Running on device: $device"
    cd wear && flutter run -d "$device"

# Build wear debug APK
wear-build:
    cd wear && flutter build apk --debug

# View wear logs
wear-logs:
    adb logcat | grep -E "(BroWear|flutter|Fatal|FATAL|Exception)"

# ─────────────────────────────────────────────────────────────
# App (unified bro app - Linux + Android)
# ─────────────────────────────────────────────────────────────

# Sync models.json to app assets
sync-models:
    mkdir -p app/assets
    cp models.json app/assets/models.json
    @echo "Synced models.json to app/assets/"

# Clean app build cache
clean-app:
    cd app && flutter clean

# Run app on Linux desktop
app: sync-models
    cd app && flutter run -d linux

# Run app on Android emulator
app-android: sync-models
    #!/usr/bin/env bash
    device=$(adb devices | grep emulator | head -1 | cut -f1)
    if [ -z "$device" ]; then
        echo "No emulator found. Run 'just emu-phone' first."
        exit 1
    fi
    cd app && flutter run -d "$device"

# Run app on real Android device (A065)
app-device: sync-models
    #!/usr/bin/env bash
    device=$(flutter devices 2>/dev/null | grep "A065" | grep -oP '(?<=• )[^ ]+(?= •)' | head -1)
    if [ -z "$device" ]; then
        echo "No A065 device found. Connect via Wireless debugging."
        exit 1
    fi
    echo "Running on device: $device"
    cd app && flutter run -d "$device"

# Build Linux desktop app
app-build-linux: sync-models
    cd app && flutter build linux

# Build Android APK
app-build-android: sync-models
    cd app && flutter build apk --debug

# ─────────────────────────────────────────────────────────────
# LiveKit Server Stack (for desktop app)
# ─────────────────────────────────────────────────────────────

# Start Redis for LiveKit
lk-redis:
    docker run -d --name bro-redis -p 6379:6379 redis:7 redis-server --bind 0.0.0.0

# Start LiveKit server (dev mode)
lk-server:
    livekit-server --dev --redis-host localhost:6379

# Start Egress service
lk-egress:
    #!/usr/bin/env bash
    mkdir -p recordings
    chmod 777 recordings
    docker run --rm --network host \
        -e EGRESS_CONFIG_BODY="log_level: debug
    api_key: ${LIVEKIT_API_KEY}
    api_secret: ${LIVEKIT_API_SECRET}
    ws_url: ws://localhost:7880
    insecure: true
    redis:
      address: localhost:6379" \
        -v $(pwd)/recordings:/out \
        livekit/egress:latest

# Stop Redis container
lk-redis-stop:
    docker stop bro-redis && docker rm bro-redis

# Start all services with pm2 (redis, livekit, egress, agent)
run:
    pm2 delete all 2>/dev/null || true
    pm2 start ecosystem.config.cjs

# View logs for a specific process (e.g., just logs agent)
logs process:
    pm2 logs {{process}}

# View all logs
logs-all:
    pm2 logs

# Stop all backend services
backend-stop:
    pm2 stop all

# Kill and delete all pm2 processes
backend-kill:
    pm2 kill

# Restart a specific process (e.g., just restart agent)
restart process:
    pm2 restart {{process}}

# Show pm2 process status
backend-status:
    pm2 status

# ─────────────────────────────────────────────────────────────
# Dev
# ─────────────────────────────────────────────────────────────

# Get all dependencies
deps:
    cd wear && flutter pub get
    cd app && flutter pub get

# Clean builds
clean:
    cd wear && flutter clean
    cd app && flutter clean

# Lint
lint:
    cd wear && flutter analyze
    cd app && flutter analyze

# Format code
fmt:
    cd wear && dart format lib/
    cd app && dart format lib/

# ─────────────────────────────────────────────────────────────
# Python (shared monorepo)
# ─────────────────────────────────────────────────────────────

# Sync all Python dependencies
deps-py:
    uv sync --group dev

# Lint Python code
lint-py:
    uv run ruff check agent ai

# Auto-fix Python lint issues
fix-py:
    uv run ruff check agent ai --fix

# Type check Python code
typecheck-py:
    uv run ty check agent ai

# Run all Python checks (lint + typecheck)
check-py:
    uv run ruff check agent ai && uv run ty check agent ai

# ─────────────────────────────────────────────────────────────
# STT Agent (LiveKit transcription worker)
# ─────────────────────────────────────────────────────────────

# Run STT agent worker
agent:
    uv run python -m agent.voice_agent dev

# ─────────────────────────────────────────────────────────────
# AI Server
# ─────────────────────────────────────────────────────────────

# Run AI server
ai:
    uv run uvicorn ai.server:app --reload --host 0.0.0.0 --port 8000

# ─────────────────────────────────────────────────────────────
# Frontend
# ─────────────────────────────────────────────────────────────

# Run frontend dev server
fe:
    cd ai/frontend && npm run dev

# Build frontend for production
fe-build:
    cd ai/frontend && npm run build

# Install frontend dependencies
fe-deps:
    cd ai/frontend && npm install

# Run both AI server and frontend (requires parallel execution)
dev:
    #!/usr/bin/env bash
    trap 'kill 0' EXIT
    (uv run uvicorn ai.server:app --reload --host 0.0.0.0 --port 8000) &
    (cd ai/frontend && npm run dev -- --port 5173) &
    wait
