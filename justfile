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

# Build phone APK
phone-build:
    cd phone && flutter build apk --debug

# ─────────────────────────────────────────────────────────────
# Dev
# ─────────────────────────────────────────────────────────────

# Get all dependencies
deps:
    cd wear && flutter pub get
    cd phone && flutter pub get

# Clean builds
clean:
    cd wear && flutter clean
    cd phone && flutter clean

# Lint
lint:
    cd wear && flutter analyze

# Format code
fmt:
    cd wear && dart format lib/
    cd phone && dart format lib/

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
