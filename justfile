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
# Phone
# ─────────────────────────────────────────────────────────────

# Run phone app on emulator (finds first emulator device)
phone:
    #!/usr/bin/env bash
    device=$(adb devices | grep emulator | head -1 | cut -f1)
    if [ -z "$device" ]; then
        echo "No emulator found. Run 'just emu-phone' first."
        exit 1
    fi
    cd phone && flutter run -d "$device"

# Run phone app on real Android device (A065)
phone-device:
    #!/usr/bin/env bash
    device=$(flutter devices 2>/dev/null | grep "A065" | grep -oP '(?<=• )[^ ]+(?= •)' | head -1)
    if [ -z "$device" ]; then
        echo "No A065 device found. Connect via Wireless debugging."
        exit 1
    fi
    echo "Running on device: $device"
    cd phone && flutter run -d "$device"

# Build phone APK
phone-build:
    cd phone && flutter build apk --debug

# ─────────────────────────────────────────────────────────────
# Desktop
# ─────────────────────────────────────────────────────────────

# Run desktop app
desktop:
    cd desktop && flutter run -d linux

# Build desktop app
desktop-build:
    cd desktop && flutter build linux

# ─────────────────────────────────────────────────────────────
# LiveKit Server Stack (for desktop app)
# ─────────────────────────────────────────────────────────────

# Start Redis for LiveKit
lk-redis:
    docker run -d --name bro-redis -p 6379:6379 redis:7 redis-server --bind 0.0.0.0

# Start LiveKit server (dev mode)
lk-server:
    livekit-server --dev --redis-host localhost:6379

# Start Egress service (copy egress-config.yaml.example first)
lk-egress:
    #!/usr/bin/env bash
    if [ ! -f egress-config.yaml ]; then
        echo "Missing egress-config.yaml. Copy from example:"
        echo "  cp egress-config.yaml.example egress-config.yaml"
        exit 1
    fi
    mkdir -p recordings
    docker run --rm --network host \
        -e EGRESS_CONFIG_FILE=/config/config.yaml \
        -v $(pwd)/egress-config.yaml:/config/config.yaml \
        -v $(pwd)/recordings:/out \
        livekit/egress:latest

# Stop Redis container
lk-redis-stop:
    docker stop bro-redis && docker rm bro-redis

# Full LiveKit stack (run in separate terminals)
lk-stack:
    @echo "Run these in separate terminals:"
    @echo "  1. just lk-redis"
    @echo "  2. just lk-server"
    @echo "  3. just lk-egress"

# ─────────────────────────────────────────────────────────────
# Dev
# ─────────────────────────────────────────────────────────────

# Get all dependencies
deps:
    cd wear && flutter pub get
    cd phone && flutter pub get
    cd desktop && flutter pub get

# Clean builds
clean:
    cd wear && flutter clean
    cd phone && flutter clean
    cd desktop && flutter clean

# Lint
lint:
    cd wear && flutter analyze
    cd desktop && flutter analyze

# Format code
fmt:
    cd wear && dart format lib/
    cd phone && dart format lib/
    cd desktop && dart format lib/

# ─────────────────────────────────────────────────────────────
# AI Server
# ─────────────────────────────────────────────────────────────

# Run AI server
ai:
    cd ai && uv run uvicorn server:app --reload --host 0.0.0.0 --port 8000

# Sync AI dependencies
ai-deps:
    cd ai && uv sync

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
    (cd ai && uv run uvicorn server:app --reload --host 0.0.0.0 --port 8000) &
    (cd ai/frontend && npm run dev -- --port 5173) &
    wait
