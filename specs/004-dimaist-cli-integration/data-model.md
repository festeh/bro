# Data Model: Dimaist CLI Integration

**Date**: 2026-01-10
**Feature**: 004-dimaist-cli-integration

## Overview

Minimal data structures. The CLI is the contract for Dimaist data (returns raw JSON). The LLM handles conversation context and pending confirmations implicitly.

## External Data (from Dimaist CLI)

Raw JSON from CLI - no Python dataclasses. Example:

```json
[{"id": 1, "title": "Buy milk", "due_date": "2026-01-12", "project": {"name": "Personal"}}]
```

## Internal Types

```python
@dataclass
class AgentResponse:
    """Response from task agent to main agent."""
    text: str
    exit_reason: str | None = None

    @property
    def should_exit(self) -> bool:
        return self.exit_reason is not None


@dataclass
class Message:
    """Conversation message."""
    role: str  # "user" or "assistant"
    content: str


@dataclass
class TaskAgentState:
    """Minimal state - LLM handles the rest via conversation history."""
    session_id: str
    messages: list[Message] = field(default_factory=list)
    active: bool = True
    pending_command: list[str] | None = None  # CLI args for button confirm
```

## Flow

**Voice input:**
1. Main agent routes to TaskAgent while `is_active`
2. TaskAgent builds system prompt with CLI help + date/time
3. LLM sees conversation history, decides action
4. If action needs confirmation: LLM sets `pending_command`, asks user
5. User confirms via voice ("yes", "alrighty") → LLM interprets and executes
6. TaskAgent returns `AgentResponse(exit_reason=...)` when done

**Button input:**
1. Frontend shows confirm/decline buttons when `has_pending` is true
2. User presses confirm → `task_agent.confirm()` executes `pending_command` directly
3. User presses decline → `task_agent.decline()` clears `pending_command`
4. No LLM call needed for button presses
