# Task Agent Interface Contract

**Date**: 2026-01-10
**Feature**: 004-dimaist-cli-integration

## Overview

This document defines the interface between bro's main agent and the task agent sub-flow.

## TaskAgent Class Interface

```python
from langgraph.graph.state import CompiledStateGraph

class TaskAgent:
    """Task agent for task management via Dimaist CLI.

    Uses LangGraph app for state persistence via namespaced thread IDs.
    """

    def __init__(
        self,
        app: CompiledStateGraph,
        session_id: str,
        cli_path: str = "dimaist-cli",
    ) -> None:
        """Initialize task agent.

        Args:
            app: Existing LangGraph app for state persistence
            session_id: Session ID (will be prefixed with "task:")
            cli_path: Path to dimaist-cli binary
        """
        self._app = app
        self._thread_id = f"task:{session_id}"
        self._cli = DimaistCLI(cli_path)
        ...

    async def start_session(self) -> str:
        """Start a new task management session.

        Returns:
            Session ID for tracking
        """
        ...

    async def process_message(self, user_message: str) -> AgentResponse:
        """Process a user message within the task management context.

        Args:
            user_message: The user's spoken/transcribed input

        Returns:
            AgentResponse with text to speak and state information
        """
        ...

    async def end_session(self) -> None:
        """End the current task management session."""
        ...

    async def confirm(self) -> AgentResponse:
        """Execute pending command (button press - no LLM)."""
        ...

    async def decline(self) -> AgentResponse:
        """Cancel pending command (button press - no LLM)."""
        ...

    @property
    def is_active(self) -> bool:
        """Whether the task agent is currently handling the conversation."""
        ...

    @property
    def has_pending(self) -> bool:
        """Whether there's a command awaiting confirmation (for UI button state)."""
        ...

    @property
    def current_datetime(self) -> str:
        """Current date and time in local timezone.

        Returns ISO format string, e.g., "2026-01-11T14:30:00-05:00"
        Used for natural language date parsing context.
        """
        ...

    @property
    def today(self) -> str:
        """Current date in YYYY-MM-DD format for CLI commands."""
        ...
```

## AgentResponse Type

```python
@dataclass
class AgentResponse:
    """Response from task agent to main agent."""

    text: str
    """Text to speak to user via TTS."""

    exit_reason: str | None = None
    """If set, return control to main agent with this reason."""

    @property
    def should_exit(self) -> bool:
        """Whether to return control to main agent."""
        return self.exit_reason is not None
```

## Integration Points

### 1. Intent Detection (in voice_agent.py)

```python
# In ChatAgent or main agent logic
class ChatAgent:
    def __init__(self, app: CompiledGraph, session_id: str, ...):
        self._app = app
        self._session_id = session_id
        self._task_agent: TaskAgent | None = None

    async def handle_user_message(self, message: str) -> str:
        intent = await classify_intent(message)

        if intent == "task_management":
            if self._task_agent is None:
                self._task_agent = TaskAgent(self._app, self._session_id)
                await self._task_agent.start_session()
            response = await self._task_agent.process_message(message)
            if response.should_exit:
                await self._task_agent.end_session()
                self._task_agent = None
            return response.text

        # ... handle other intents
```

### 2. Session Lifecycle

```
Main Agent                          Task Agent
    |                                    |
    |--- task_management intent -------->|
    |                                    |--- start_session()
    |<-- AgentResponse(text="...") ------|
    |                                    |
    |--- user message ------------------>|
    |                                    |--- process_message()
    |<-- AgentResponse(pending=True) ----|
    |                                    |
    |--- "yes" / "no" ------------------>|
    |                                    |--- process_message()
    |<-- AgentResponse(text="Done") -----|
    |                                    |
    |--- topic change ------------------>|
    |                                    |--- detect non-task intent
    |<-- AgentResponse(should_exit=True)-|
    |                                    |--- end_session()
    |                                    |
```

### 3. CLI Wrapper Interface

```python
class DimaistCLI:
    """Wrapper for dimaist-cli subprocess execution.

    Returns raw dicts/lists - no Python data model to keep in sync.
    CLI help text is injected into agent's system prompt.
    """

    def __init__(self, cli_path: str | None = None) -> None:
        ...

    async def run(self, *args: str) -> dict | list:
        """Execute CLI command and return parsed JSON.

        Examples:
            await cli.run("task", "list")
            await cli.run("task", "create", "--title", "Buy milk", "--due", "2026-01-12")
            await cli.run("task", "complete", "42")
        """
        ...

    async def get_help(self) -> str:
        """Get CLI help text for agent context."""
        ...

    async def check_available(self) -> bool:
        """Check if CLI is available and working."""
        ...
```

## Error Handling Contract

```python
class CLIError(Exception):
    """CLI command failed."""

    def __init__(self, message: str, returncode: int = 1):
        self.returncode = returncode
```

## Logging Requirements

All task agent operations must log with structured format:

```python
logger.info(
    "task_agent_action",
    session_id=self._session_id,
    action="create_task",
    task_title="buy groceries",
    status="pending_confirmation",
)
```

Required log events:
- `task_agent_session_start`
- `task_agent_session_end`
- `task_agent_action` (with action type and status)
- `task_agent_cli_call` (with command and duration)
- `task_agent_error` (with error type and message)
