# Implementation Plan: Python Type Safety

**Branch**: `003-python-type-safety` | **Date**: 2026-01-10 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/003-python-type-safety/spec.md`

## Summary

Add type safety tooling to the Python agent code using ruff for linting/formatting and ty for type checking. Configure both tools in pyproject.toml and add complete type annotations to existing code. Provide uv-based commands for running checks.

## Technical Context

**Language/Version**: Python 3.11+
**Primary Dependencies**: ruff (linter/formatter), ty (type checker)
**Storage**: N/A (tooling configuration only)
**Testing**: Commands exit codes (0 = pass, non-zero = fail)
**Target Platform**: Cross-platform (Linux, macOS, Windows)
**Project Type**: Single project (agent directory)
**Performance Goals**: <10 seconds for full check on current codebase
**Constraints**: Must integrate with existing uv workflow
**Scale/Scope**: 2 Python files (~600 LOC), ~10 functions needing annotations

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Services | N/A | Tooling doesn't affect architecture |
| II. Type Safety | **IMPLEMENTS** | This feature directly fulfills this principle |
| III. DRY with Pragmatism | PASS | No abstractions being added |
| IV. Structured Logging | N/A | Tooling doesn't affect logging |
| V. Break Things First | PASS | Adding new tooling, no backwards compatibility needed |

**Gate Status**: PASS - Feature directly implements Constitution Principle II (Type Safety)

## Project Structure

### Documentation (this feature)

```text
specs/003-python-type-safety/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Tool research and configuration decisions
├── quickstart.md        # Developer usage guide
└── tasks.md             # Implementation tasks (created by /speckit.tasks)
```

### Source Code (repository root)

```text
agent/
├── constants.py         # String constants (minimal typing needed)
├── voice_agent.py       # Main agent code (type annotations to add)
└── pyproject.toml       # Add ruff and ty configuration here
```

**Structure Decision**: Existing `agent/` directory structure maintained. No new files created except configuration additions to `pyproject.toml`.

## Complexity Tracking

No violations - this feature adds minimal complexity (configuration only).

## Implementation Approach

### Phase 1: Configuration

1. Add ruff and ty as dev dependencies in pyproject.toml
2. Configure ruff rules: F, E, B, I, UP, C4
3. Configure ty for Python 3.11 with standard strictness
4. Add script commands for lint, typecheck, fix, and check-all

### Phase 2: Type Annotations

1. Add return type annotations to all functions in voice_agent.py
2. Fix any type errors revealed by ty
3. Add `# type: ignore` comments for untyped third-party code if needed

### Phase 3: Validation

1. Run `uv run ruff check .` - should pass with 0 errors
2. Run `uv run ty check .` - should pass with 0 errors
3. Verify auto-fix works: `uv run ruff check . --fix`

## Commands Reference

After implementation, developers will use:

```bash
# From agent/ directory
uv run ruff check .          # Lint check
uv run ruff check . --fix    # Auto-fix lint issues
uv run ruff format .         # Format code
uv run ty check .            # Type check

# Combined check (for CI/pre-commit)
uv run ruff check . && uv run ty check .
```
