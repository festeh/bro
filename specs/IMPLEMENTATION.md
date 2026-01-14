# Implementation Rules

## 1. Use local source code

Never fetch source from the web. Read from local directories.

**Source directories for this project:**
- `.venv/lib/python3.12/site-packages/` - Python dependencies
- `ai/frontend/node_modules/` - Node.js dependencies
- `~/.pub-cache/hosted/pub.dev/` - Dart/Flutter dependencies
- `phone/android/app/src/main/kotlin/` - Phone app Kotlin sources
- `wear/android/app/src/main/kotlin/` - Wear app Kotlin sources
- `shared/opus/src/main/java/` - Shared Kotlin/Java sources

## 2. Debug with logs, not guesses

Set up logging. Demand access to logs. Find the root cause before fixing.

## 3. Prefer smaller code over backwards compatibility

Delete deprecated code. Don't add shims or fallbacks.

## 4. Write DRY code

Extract shared logic. Avoid copy-paste.

## 5. Build deep modules

Simple interface, complex implementation. Hide details that might change. Avoid shallow wrappers that just pass data through.
