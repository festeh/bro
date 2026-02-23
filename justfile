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
    cd app && flutter run --flavor wear -t lib/main_wear.dart -d "$device"

# Run wear app on real Samsung watch (SM-* device)
wear-device:
    #!/usr/bin/env bash
    device=$(flutter devices 2>/dev/null | grep "SM " | grep -oP '(?<=• )[^ ]+(?= •)' | head -1)
    if [ -z "$device" ]; then
        echo "No Samsung watch found. Connect via Wireless debugging."
        exit 1
    fi
    echo "Running on device: $device"
    cd app && flutter run --flavor wear -t lib/main_wear.dart -d "$device" \
        --dart-define=LIVEKIT_URL=wss://$BRO_HOST \
        --dart-define=LIVEKIT_API_KEY=$BRO_LIVEKIT_API_KEY \
        --dart-define=LIVEKIT_API_SECRET=$BRO_LIVEKIT_API_SECRET \
        --dart-define=AI_BASE_URL=$AI_BASE_URL \
        --dart-define=AI_API_KEY=$AI_API_KEY

# Build wear release APK
wear-build:
    cd app && flutter build apk --flavor wear -t lib/main_wear.dart \
        --dart-define=LIVEKIT_URL=wss://$BRO_HOST \
        --dart-define=LIVEKIT_API_KEY=$BRO_LIVEKIT_API_KEY \
        --dart-define=LIVEKIT_API_SECRET=$BRO_LIVEKIT_API_SECRET \
        --dart-define=AI_BASE_URL=$AI_BASE_URL \
        --dart-define=AI_API_KEY=$AI_API_KEY

# View wear logs
wear-logs:
    adb logcat | grep -E "(BroWear|flutter|Fatal|FATAL|Exception)"

# ─────────────────────────────────────────────────────────────
# App (unified bro app - Linux + Android)
# ─────────────────────────────────────────────────────────────

# Clean app build cache
clean-app:
    cd app && flutter clean

# Run app on Linux desktop (connects to remote server)
app:
    cd app && flutter run -d linux \
        --dart-define=LIVEKIT_URL=wss://$BRO_HOST \
        --dart-define=LIVEKIT_API_KEY=$BRO_LIVEKIT_API_KEY \
        --dart-define=LIVEKIT_API_SECRET=$BRO_LIVEKIT_API_SECRET \
        --dart-define=AI_BASE_URL=$AI_BASE_URL \
        --dart-define=AI_API_KEY=$AI_API_KEY

# Run app on Android emulator
app-android:
    #!/usr/bin/env bash
    device=$(adb devices | grep emulator | head -1 | cut -f1)
    if [ -z "$device" ]; then
        echo "No emulator found. Run 'just emu-phone' first."
        exit 1
    fi
    cd app && flutter run -d "$device"

# Run app on real Android device (A065)
app-device:
    #!/usr/bin/env bash
    device=$(flutter devices 2>/dev/null | grep "A065" | grep -oP '(?<=• )[^ ]+(?= •)' | head -1)
    if [ -z "$device" ]; then
        echo "No A065 device found. Connect via Wireless debugging."
        exit 1
    fi
    echo "Running on device: $device"
    cd app && flutter run -d "$device"

# Build Linux desktop app
app-build-linux:
    cd app && flutter build linux

# Build Android APK (release, localhost)
app-build-android:
    cd app && flutter build apk --flavor phone

# Build Android APK for production (requires BRO_HOST, LIVEKIT_API_KEY, LIVEKIT_API_SECRET in .env)
app-build-android-prod:
    cd app && flutter build apk --flavor phone \
        --dart-define=LIVEKIT_URL=wss://$BRO_HOST \
        --dart-define=LIVEKIT_HTTP_URL=https://$BRO_HOST \
        --dart-define=LIVEKIT_API_KEY=$BRO_LIVEKIT_API_KEY \
        --dart-define=LIVEKIT_API_SECRET=$BRO_LIVEKIT_API_SECRET \
        --dart-define=AI_BASE_URL=$AI_BASE_URL \
        --dart-define=AI_API_KEY=$AI_API_KEY

# Build and deploy phone APK to pCloud
deploy-phone: app-build-android-prod
    cp app/build/app/outputs/flutter-apk/app-phone-release.apk ~/pCloudDrive/android-apps/bro/

# ─────────────────────────────────────────────────────────────
# Backend (pm2)
# ─────────────────────────────────────────────────────────────

# Start all services with pm2 (redis, livekit, egress, agent, app)
run:
    pm2 delete all 2>/dev/null || true
    pm2 start ecosystem.config.cjs

# Stop all backend services
stop:
    pm2 stop all

# Kill and delete all pm2 processes
kill:
    pm2 kill

# Restart a specific process (e.g., just restart agent)
restart process:
    pm2 restart {{process}}

# Show pm2 process status
status:
    pm2 status

# View logs for a specific process (e.g., just logs agent)
logs process:
    pm2 logs {{process}}

# View all logs
logs-all:
    pm2 logs

# ─────────────────────────────────────────────────────────────
# Dev
# ─────────────────────────────────────────────────────────────

# Get all dependencies
deps:
    cd app && flutter pub get

# Clean builds
clean:
    cd app && flutter clean

# Lint
lint:
    cd app && flutter analyze
    uv run ruff check agent

# Format code
fmt:
    cd app && dart format lib/
    uv run ruff format agent

# ─────────────────────────────────────────────────────────────
# Python (shared monorepo)
# ─────────────────────────────────────────────────────────────

# Sync all Python dependencies
deps-py:
    uv sync --group dev

# Lint Python code
lint-py:
    uv run ruff check agent

# Auto-fix Python lint issues
fix-py:
    uv run ruff check agent --fix

# Type check Python code
typecheck-py:
    uv run ty check agent

# Run all Python checks (lint + typecheck)
check-py:
    uv run ruff check agent && uv run ty check agent

# ─────────────────────────────────────────────────────────────
# Frontend (lives in ../my-agents/frontend)
# ─────────────────────────────────────────────────────────────

# Run frontend dev server
fe:
    cd ../my-agents/frontend && npm run dev

# Build frontend for production
fe-build:
    cd ../my-agents/frontend && npm run build

# Install frontend dependencies
fe-deps:
    cd ../my-agents/frontend && npm install

# Run both AI server and frontend (requires parallel execution)
dev:
    #!/usr/bin/env bash
    trap 'kill 0' EXIT
    (uv run uvicorn my_agents.server:app --reload --host 0.0.0.0 --port 8000) &
    (cd ../my-agents/frontend && npm run dev -- --port 5173) &
    wait
