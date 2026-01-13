# Data Model: Agent Test REPL

**Feature**: 005-agent-test-repl
**Date**: 2026-01-12

## Overview

The REPL has minimal data model requirements since it leverages existing TaskAgent state management. This document describes REPL-specific data structures.

## Entities

### REPLSession (in-memory only)

Represents the current REPL session state. Not persisted.

| Field | Type | Description |
|-------|------|-------------|
| agent | TaskAgent | The underlying TaskAgent instance |
| running | bool | Whether the REPL loop is active |

### REPLCommand

Represents a parsed REPL control command.

| Field | Type | Description |
|-------|------|-------------|
| name | str | Command name without prefix (e.g., "help", "exit") |
| args | list[str] | Optional command arguments |

**Supported Commands**:
- `/help` - Display available commands and usage
- `/exit` - Terminate the REPL session

## Reused from TaskAgent

The REPL delegates all agent state to the existing `TaskAgent` class:

- `TaskAgentState` - Conversation history, pending commands
- `AgentResponse` - Response text and exit signals
- `Message` - User/assistant message pairs

See `agent/task_agent.py` for details.

## State Diagram

```
┌─────────────┐
│   START     │
└──────┬──────┘
       │
       ▼
┌─────────────┐    /exit or Ctrl+C    ┌─────────────┐
│   RUNNING   │ ───────────────────►  │    EXIT     │
│             │                       │             │
│  • Read     │                       └─────────────┘
│  • Process  │
│  • Print    │
│             │
└─────────────┘
       │
       │ error
       ▼
┌─────────────┐
│   ERROR     │ ──► display message ──► back to RUNNING
└─────────────┘
```

## No Persistence

Per clarification: "Ephemeral only - sessions exist in memory, lost on exit"

- No file I/O
- No database
- No serialization
