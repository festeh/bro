# Research: Dimaist CLI Integration

**Date**: 2026-01-10
**Feature**: 004-dimaist-cli-integration

## Research Topics

### 1. Task Agent Pattern for Sub-Flows

**Decision**: TaskAgent class that uses existing LangGraph app for state persistence

**Rationale**:
- Clean class interface for `voice_agent.py` (matches `ChatAgent`, `TranscribeAgent` pattern)
- State persistence via existing LangGraph checkpointer (no new infrastructure)
- Namespaced thread IDs (`task:{session_id}`) separate task state from main conversation
- Python asyncio provides clean subprocess management for CLI execution

**Implementation**:
```python
class TaskAgent:
    def __init__(self, app, thread_id: str):
        self._app = app  # Existing LangGraph app
        self._thread_id = f"task:{thread_id}"

    async def process_message(self, message: str) -> AgentResponse:
        config = {"configurable": {"thread_id": self._thread_id}}
        state = await self._app.aget_state(config)
        # ... task logic ...
        await self._app.aupdate_state(config, new_state)
```

**Alternatives Considered**:
- Pure Python class (no LangGraph): Simpler but loses state persistence across restarts
- LangGraph sub-graph as separate node: More coupling, harder to test independently
- External microservice: Over-engineered for single-user CLI integration

### 2. Dimaist CLI Interface

**Decision**: Use `dimaist-cli` with JSON output parsing

**Rationale**:
- CLI outputs JSON for all commands (`printJSON` function in main.go)
- Direct CRUD commands available (no need to go through AI/LLM)

**Available Commands**:
```bash
# Read operations
dimaist-cli task list                     # JSON array of all tasks
dimaist-cli task get <id>                 # JSON single task
dimaist-cli project list                  # JSON array of all projects

# Write operations
dimaist-cli task create --title "..." [--due YYYY-MM-DD] [--project-id N]
dimaist-cli task complete <id>            # Returns {task, is_recurring}
dimaist-cli task update <id> [--title "..."] [--due "..."] [--project-id N]
dimaist-cli task delete <id>              # Returns {deleted: true, id}

```

**Key CLI Behaviors**:
- Exit code 0 on success, non-zero on error
- Errors written to stderr
- JSON output to stdout
- Requires `.env` file or `DATABASE_URL` environment variable

### 3. Intent Classification Extension

**Decision**: Add `task_management` intent to existing classification system

**Rationale**:
- Existing `graph.py` uses structured output with `IntentClassification` model
- Current intents: `direct_response`, `web_search`, `end_dialog`
- Task-related utterances should route to task agent instead of general LLM

**Classification Examples**:
- "Add a task for tomorrow" → `task_management`
- "What's on my schedule?" → `task_management`
- "Complete the groceries task" → `task_management`
- "What's the weather?" → `web_search` (not task-related)
- "Hello, how are you?" → `direct_response`

### 4. User Approval Flow

**Decision**: Agent proposes action, waits for user confirmation via voice

**Rationale**:
- Voice interface requires clear confirmation prompts
- User says "yes/confirm" to approve, "no/cancel" to reject
- Agent must not execute until affirmative response received

**Implementation Approach**:
- Task agent maintains `pending_action` state
- On destructive operation, set pending and prompt user
- Next user turn checks for confirmation words
- Execute or cancel based on response

### 5. CLI Execution Strategy

**Decision**: Use `asyncio.create_subprocess_exec` with JSON parsing

**Rationale**:
- Non-blocking execution in async context
- Clean separation of stdout (JSON) and stderr (errors)
- Timeout handling for hung CLI processes

**Code Pattern**:
```python
async def run_cli(*args: str, timeout: float = 30.0) -> dict:
    proc = await asyncio.create_subprocess_exec(
        "dimaist-cli", *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await asyncio.wait_for(
        proc.communicate(), timeout=timeout
    )
    if proc.returncode != 0:
        raise CLIError(stderr.decode())
    return json.loads(stdout.decode())
```

### 6. Natural Language Date Parsing

**Decision**: Use LLM to convert natural language dates to ISO format, with current date/time injected into context

**Rationale**:
- Dimaist CLI expects `YYYY-MM-DD` or RFC3339 format
- User says "tomorrow", "next Friday", "in 3 days"
- Task agent's LLM call can include date conversion in tool parameters

**Implementation**:
- TaskAgent uses system local timezone automatically
- `current_datetime` and `today` properties provide formatted date/time strings
- System prompt includes current date/time context
- LLM uses this context to resolve relative dates (e.g., "tomorrow" → "2026-01-12")
- No separate date parsing library needed

**Code Pattern**:
```python
# In TaskAgent
def _build_system_prompt(self) -> str:
    return f"""You are a task management assistant.
Current date: {self.today}
Current time: {self.current_datetime}

When the user mentions relative dates like "tomorrow" or "next Friday",
convert them to YYYY-MM-DD format for the CLI commands.
"""
```

### 7. Task Matching for Completion

**Decision**: Agent uses adaptive matching (exact → fuzzy)

**Rationale**:
- User says "complete groceries" but task is "buy groceries"
- First attempt exact match on title
- If no match, fuzzy search by querying task list and LLM-assisted selection

**Implementation**:
- `dimaist-cli task list` returns all tasks
- Agent searches for matching task
- If ambiguous, presents options to user

## Dependencies

| Dependency | Purpose | Already in Project |
|------------|---------|-------------------|
| asyncio | Subprocess management | Yes (Python stdlib) |
| json | CLI output parsing | Yes (Python stdlib) |
| livekit-agents | Agent framework | Yes |
| langgraph | State persistence via existing app | Yes (in ai/) |
| dimaist-cli | Task management CLI | External (must be in PATH) |

## Environment Requirements

| Variable | Purpose | Required |
|----------|---------|----------|
| DATABASE_URL | PostgreSQL connection for dimaist-cli | Yes (for CLI) |
| DIMAIST_CLI_PATH | Optional: custom path to CLI binary | No (defaults to PATH lookup) |

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| CLI not in PATH | Agent cannot execute tasks | Check CLI availability on startup, log warning |
| CLI hangs | Agent becomes unresponsive | Timeout on subprocess calls (30s default) |
| Database unavailable | All CLI commands fail | Catch errors, inform user, suggest retry |
| Concurrent modification | Task state inconsistent | Accept eventual consistency; user can refresh |
