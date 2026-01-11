# Implementation Plan: Dimaist CLI Integration

**Branch**: `004-dimaist-cli-integration` | **Date**: 2026-01-10 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/004-dimaist-cli-integration/spec.md`

## Summary

Integrate bro's voice agent with Dimaist task manager by creating a TaskAgent class that spawns `dimaist-cli` commands. The TaskAgent uses the existing LangGraph app and checkpointer for state persistence, providing a clean class interface while leveraging shared infrastructure. The main agent detects `task_management` intent and delegates to the task agent, which handles multi-turn conversations, user approval flows, and CLI execution. All database-modifying operations require explicit user confirmation.

## Technical Context

**Language/Version**: Python 3.11+ (matching existing agent codebase)
**Primary Dependencies**: livekit-agents (existing), langgraph (existing), asyncio subprocess for CLI execution
**Storage**: N/A (Dimaist manages its own PostgreSQL; bro only invokes CLI)
**Testing**: pytest with mocked subprocess calls
**Target Platform**: Linux server (same as existing agent)
**Project Type**: Single service extension (adding to existing `agent/` module)
**Performance Goals**: <10s for single-turn operations, <5s for query responses
**Constraints**: CLI must be available at known path, DATABASE_URL env var required for dimaist-cli
**Scale/Scope**: Single user, local machine integration

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Modular Services | PASS | Task agent is a separate component, communicates via CLI subprocess |
| II. Type Safety | PASS | Will use Python type hints, mypy/ty validation |
| III. DRY with Pragmatism | PASS | No premature abstractions; task agent is single-purpose |
| IV. Structured Logging | PASS | Will use existing logger patterns from voice_agent.py |
| V. Break Things First | PASS | New feature, no backwards compatibility concerns |

## Project Structure

### Documentation (this feature)

```text
specs/004-dimaist-cli-integration/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
agent/
├── voice_agent.py       # Existing - add task_management intent routing
├── constants.py         # Existing - add task agent constants
├── task_agent.py        # NEW - task agent implementation
└── dimaist_cli.py       # NEW - CLI wrapper with subprocess execution

ai/
├── graph.py             # Existing - add task_management to IntentClassification
└── models.py            # Existing - update IntentClassification enum
```

**Structure Decision**: Extend existing `agent/` module with new task agent files. TaskAgent is a Python class that:
- Receives the existing LangGraph app as a dependency
- Uses namespaced thread IDs (`task:{session_id}`) for state persistence
- Spawns `dimaist-cli` commands via asyncio subprocess
- Shares the SQLite checkpointer with the main conversation graph

## Architecture: TaskAgent + LangGraph

```
┌─────────────────────────────────────────────────────────────┐
│ voice_agent.py (ChatAgent)                                  │
│                                                             │
│  ┌─────────────┐     ┌──────────────────────────────────┐  │
│  │ Intent      │────▶│ TaskAgent                        │  │
│  │ Classifier  │     │                                  │  │
│  │             │     │  - process_message()             │  │
│  │ task_mgmt ──┼────▶│  - uses app.aget_state/update    │  │
│  └─────────────┘     │  - spawns dimaist-cli            │  │
│                      └──────────────────────────────────┘  │
│                                   │                         │
│                                   ▼                         │
│                      ┌──────────────────────────────────┐  │
│                      │ LangGraph App (ai/graph.py)      │  │
│                      │                                  │  │
│                      │  thread: "main:{id}" - chat      │  │
│                      │  thread: "task:{id}" - tasks     │  │
│                      │                                  │  │
│                      │  AsyncSqliteSaver (shared)       │  │
│                      └──────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

**Benefits of this approach:**
- Clean TaskAgent class interface for voice_agent.py
- State persistence via existing SQLite checkpointer
- No separate infrastructure, shares LangGraph app
- Could survive agent restarts if needed

## Complexity Tracking

No constitution violations requiring justification.
