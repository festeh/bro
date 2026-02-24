# Bro - WearOS VAD App

set dotenv-load

wear_avd := "Virtual_Wearable"
phone_avd := "Pixel_8_Pro"

default:
    @just --list

# ─────────────────────────────────────────────────────────────
# Emulator
# ─────────────────────────────────────────────────────────────

# Start emulator (wear or phone)
emu type:
    #!/usr/bin/env bash
    case "{{type}}" in
        wear)  emulator -avd {{wear_avd}} ;;
        phone) emulator -avd {{phone_avd}} ;;
        *) echo "Unknown type: {{type}}. Use 'wear' or 'phone'." && exit 1 ;;
    esac

# Kill all emulators
emu-kill:
    adb devices | grep emulator | cut -f1 | xargs -I {} adb -s {} emu kill

# List connected devices
devices:
    adb devices -l

# ─────────────────────────────────────────────────────────────
# App
# ─────────────────────────────────────────────────────────────

# Run app (linux, android, wear, wear-device, phone-device)
app target='linux':
    #!/usr/bin/env bash
    DEFS="--dart-define=LIVEKIT_URL=wss://$BRO_HOST \
        --dart-define=LIVEKIT_API_KEY=$BRO_LIVEKIT_API_KEY \
        --dart-define=LIVEKIT_API_SECRET=$BRO_LIVEKIT_API_SECRET \
        --dart-define=AI_BASE_URL=$AI_BASE_URL \
        --dart-define=AI_API_KEY=$AI_API_KEY"
    case "{{target}}" in
        linux)
            cd app && flutter run -d linux $DEFS
            ;;
        android)
            device=$(adb devices | grep emulator | head -1 | cut -f1)
            if [ -z "$device" ]; then
                echo "No emulator found. Run 'just emu phone' first."
                exit 1
            fi
            cd app && flutter run -d "$device"
            ;;
        wear)
            device=$(adb devices | grep emulator | head -1 | cut -f1)
            if [ -z "$device" ]; then
                echo "No emulator found. Run 'just emu wear' first."
                exit 1
            fi
            cd app && flutter run --flavor wear -t lib/main_wear.dart -d "$device"
            ;;
        wear-device)
            device=$(flutter devices 2>/dev/null | grep "SM " | grep -oP '(?<=• )[^ ]+(?= •)' | head -1)
            if [ -z "$device" ]; then
                echo "No Samsung watch found. Connect via Wireless debugging."
                exit 1
            fi
            echo "Running on device: $device"
            cd app && flutter run --flavor wear -t lib/main_wear.dart -d "$device" $DEFS
            ;;
        phone-device)
            device=$(flutter devices 2>/dev/null | grep "A065" | grep -oP '(?<=• )[^ ]+(?= •)' | head -1)
            if [ -z "$device" ]; then
                echo "No A065 device found. Connect via Wireless debugging."
                exit 1
            fi
            echo "Running on device: $device"
            cd app && flutter run --flavor phone -d "$device" $DEFS
            ;;
        *)
            echo "Unknown target: {{target}}. Use linux, android, wear, wear-device, or phone-device."
            exit 1
            ;;
    esac

# Build app (linux, android, android-prod, wear)
build target:
    #!/usr/bin/env bash
    DEFS="--dart-define=LIVEKIT_URL=wss://$BRO_HOST \
        --dart-define=LIVEKIT_API_KEY=$BRO_LIVEKIT_API_KEY \
        --dart-define=LIVEKIT_API_SECRET=$BRO_LIVEKIT_API_SECRET \
        --dart-define=AI_BASE_URL=$AI_BASE_URL \
        --dart-define=AI_API_KEY=$AI_API_KEY"
    case "{{target}}" in
        linux)
            cd app && flutter build linux
            ;;
        android)
            cd app && flutter build apk --flavor phone
            ;;
        android-prod)
            cd app && flutter build apk --flavor phone $DEFS \
                --dart-define=LIVEKIT_HTTP_URL=https://$BRO_HOST
            ;;
        wear)
            cd app && flutter build apk --flavor wear -t lib/main_wear.dart $DEFS
            ;;
        *)
            echo "Unknown target: {{target}}. Use linux, android, android-prod, or wear."
            exit 1
            ;;
    esac

# Build and deploy phone APK to pCloud
deploy: (build "android-prod")
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

# View pm2 logs (optionally for a specific process)
logs process='':
    #!/usr/bin/env bash
    if [ -z "{{process}}" ]; then
        pm2 logs
    else
        pm2 logs "{{process}}"
    fi

# ─────────────────────────────────────────────────────────────
# Dev
# ─────────────────────────────────────────────────────────────

# Get all dependencies (flutter + python)
deps:
    cd app && flutter pub get
    uv sync --group dev

# Clean builds
clean:
    cd app && flutter clean

# Lint (dart + python)
lint:
    cd app && flutter analyze
    uv run ruff check agent

# Format code (dart + python)
fmt:
    cd app && dart format lib/
    uv run ruff format agent

# Auto-fix Python lint issues
fix:
    uv run ruff check agent --fix

# Type check Python code
typecheck:
    uv run ty check agent

# ─────────────────────────────────────────────────────────────
# Frontend (lives in ../my-agents/frontend)
# ─────────────────────────────────────────────────────────────

# Frontend (dev, build, deps)
fe cmd='dev':
    #!/usr/bin/env bash
    case "{{cmd}}" in
        dev)   cd ../my-agents/frontend && npm run dev ;;
        build) cd ../my-agents/frontend && npm run build ;;
        deps)  cd ../my-agents/frontend && npm install ;;
        *) echo "Unknown command: {{cmd}}. Use dev, build, or deps." && exit 1 ;;
    esac

# Run both AI server and frontend (requires parallel execution)
dev:
    #!/usr/bin/env bash
    trap 'kill 0' EXIT
    (uv run uvicorn my_agents.server:app --reload --host 0.0.0.0 --port 8000) &
    (cd ../my-agents/frontend && npm run dev -- --port 5173) &
    wait
