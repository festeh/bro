# Quickstart: Python Type Safety

## Overview

This feature adds type checking and linting to the Python agent code using:
- **ruff**: Fast linter and formatter (replaces flake8, isort, black)
- **ty**: Fast type checker from Astral (same vendor as ruff/uv)

## Prerequisites

- uv package manager (already installed)
- Python 3.11+ (already configured)

## Usage

All commands run from the `agent/` directory:

### Linting

```bash
# Check for issues
uv run ruff check .

# Auto-fix issues
uv run ruff check . --fix

# Format code
uv run ruff format .
```

### Type Checking

```bash
# Run type checker
uv run ty check .
```

### Combined Check (CI/Pre-commit)

```bash
# Run both lint and type check
uv run ruff check . && uv run ty check .
```

## Rule Sets Enabled

| Rule | Description |
|------|-------------|
| F | Pyflakes - undefined names, unused imports |
| E | pycodestyle - PEP 8 style |
| B | flake8-bugbear - likely bugs |
| I | isort - import ordering |
| UP | pyupgrade - modern Python syntax |
| C4 | comprehensions - optimize list/dict/set |

## Type Annotations

All functions must have type annotations:

```python
# Good
def create_stt(provider: str) -> deepgram.STT | elevenlabs.STT:
    ...

# Bad - missing return type
def create_stt(provider: str):
    ...
```

## Handling Third-Party Libraries

For libraries without type stubs, use `# type: ignore`:

```python
from untyped_library import something  # type: ignore[import-untyped]
```

## Troubleshooting

### "Unresolved import" errors
- Check that the package is in dependencies
- Add to `extra-paths` in ty config if needed

### "Missing return type" errors
- Add explicit return type annotation
- Use `-> None` for functions that don't return

### Conflicting rules
- Use `# noqa: XXXX` to ignore specific ruff rules
- Use `# type: ignore[error-code]` for ty issues
