# Research: Python Type Safety

**Feature Branch**: `003-python-type-safety`
**Date**: 2026-01-10

## Tool Selection

### Type Checker: ty

**Decision**: Use ty (Astral's type checker)

**Rationale**:
- Same vendor as ruff and uv (Astral) - consistent toolchain
- 10-100x faster than mypy/pyright
- Written in Rust for performance
- Supports pyproject.toml configuration
- Respects `type: ignore` comments for third-party libraries

**Alternatives considered**:
- mypy: Original Python type checker, widely adopted, but slower
- pyright: Fast, excellent IDE integration, but different vendor
- basedpyright: More strict pyright fork, less mainstream

### Linter: ruff

**Decision**: Use ruff (already specified in requirements)

**Rationale**:
- Extremely fast (10-100x faster than flake8/pylint)
- Combines linting, formatting, and import sorting
- Single tool replaces flake8, isort, pyupgrade, and more
- Consistent with uv package manager (same vendor)

## Configuration Decisions

### Ruff Rule Sets

**Decision**: Enable `F, E, B, I, UP, C4`

| Rule Set | Purpose |
|----------|---------|
| F | Pyflakes - undefined names, unused imports, logic errors |
| E | pycodestyle - PEP 8 style guidelines |
| B | flake8-bugbear - likely bugs and design problems |
| I | isort - import sorting and formatting |
| UP | pyupgrade - modern Python syntax suggestions |
| C4 | flake8-comprehensions - optimize comprehensions |

**Rationale**: Covers the most common issues without being overly strict. Balances catching real bugs vs. noise.

### Type Checking Strictness

**Decision**: Standard strictness with `type: ignore` for untyped libraries

**Rationale**:
- The codebase uses livekit-agents which may not have complete type stubs
- Strict mode would require adding many ignores for third-party code
- Standard mode catches real type errors while allowing library integration

### Command Interface

**Decision**: Use uv run for commands in pyproject.toml scripts

**Commands**:
- `uv run ruff check .` - Run linting
- `uv run ruff check . --fix` - Auto-fix linting issues
- `uv run ty check .` - Run type checking
- Combined: `uv run ruff check . && uv run ty check .`

**Rationale**: uv is already the package manager, keeps commands consistent.

## Current Codebase Analysis

### Files to Type-Annotate

| File | Status | Work Needed |
|------|--------|-------------|
| constants.py | Minimal | Already typed (string constants) |
| voice_agent.py | Partial | Add return types to ~10 functions |

### Functions Needing Return Types

1. `create_stt(provider: str)` → needs return type
2. `create_llm(model_key: str)` → needs return type
3. `get_settings_from_metadata(ctx: JobContext)` → needs return type
4. `prewarm(proc: JobProcess)` → needs `-> None`
5. `entrypoint(ctx: JobContext)` → needs `-> None`
6. Nested callbacks in `entrypoint` → need proper types

### Third-Party Type Considerations

- `livekit.agents`: May have incomplete stubs - will need `type: ignore` if issues
- `livekit.plugins.*`: Plugin types may be dynamic
- `numpy`: Well-typed, no issues expected
- `dotenv`: Simple types, no issues expected

## pyproject.toml Configuration

```toml
[tool.ruff]
target-version = "py311"
line-length = 100

[tool.ruff.lint]
select = ["F", "E", "B", "I", "UP", "C4"]
ignore = ["E501"]  # Line length handled by formatter

[tool.ruff.format]
quote-style = "double"

[tool.ty]
python-version = "3.11"

[tool.ty.rules]
# Warn on issues, error on critical problems
possibly-unresolved-reference = "error"

[tool.ty.src]
include = ["*.py"]
exclude = [".venv"]
```
