# Implementation Plan: Agent Test REPL

**Branch**: `005-agent-test-repl` | **Date**: 2026-01-12 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/005-agent-test-repl/spec.md`

## Summary

Add an interactive REPL (Read-Eval-Print Loop) for testing the TaskAgent without LiveKit infrastructure. The REPL accepts text input, passes it to TaskAgent, and displays structured responses showing active agent, response type, and action metadata. Supports mock mode for isolated testing without external dependencies.

## Technical Context

**Language/Version**: Python 3.11+ (matches existing codebase)
**Primary Dependencies**: asyncio (existing), pydantic (existing), langchain-openai (existing via TaskAgent)
**Storage**: N/A (sessions are ephemeral, in-memory only)
**Testing**: pytest with pytest-asyncio (existing setup)
**Target Platform**: Linux/macOS CLI (development tool)
**Project Type**: Single project - CLI module within existing agent package
**Performance Goals**: <5s startup time, <3s response display (from SC-001, SC-002)
**Constraints**: Must use existing TaskAgent without modifications to its core logic
**Scale/Scope**: Single developer use, local development only

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Services | PASS | REPL is a standalone CLI tool; uses TaskAgent via public interface only |
| II. Type Safety | PASS | Will use full type hints; TaskAgent already typed |
| III. DRY with Pragmatism | PASS | Reuses existing TaskAgent class; no premature abstractions |
| IV. Structured Logging | PASS | Will use existing logging configuration |
| V. Break Things First | N/A | New feature; no backwards compatibility concerns |

**Gate Result**: PASS - Proceed to Phase 0

## Project Structure

### Documentation (this feature)

```text
specs/005-agent-test-repl/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
agent/
├── task_agent.py        # Existing - TaskAgent class (no modifications)
├── dimaist_cli.py       # Existing - CLI wrapper
├── repl.py              # NEW - REPL implementation
└── tests/
    ├── test_task_agent.py   # Existing
    └── test_repl.py         # NEW - REPL tests
```

**Structure Decision**: Single module addition to existing `agent/` package. The REPL is a full-batteries development tool that wraps TaskAgent with real CLI integration.

## Complexity Tracking

> No violations - complexity tracking not required.
