# Plan: Persistent Task Agent Retry

**Branch**: 017-persistent-task-agent-retry

## Tech Stack

- Language: Python
- Framework: asyncio, LangChain
- Testing: pytest

## Structure

Changes in:

```
agent/
├── task_agent.py    # Add retry loop with Result pattern
└── constants.py     # Add MAX_CLI_RETRIES constant
```

## Approach

### 1. Add retry constant

Add `MAX_CLI_RETRIES = 3` to `constants.py`.

### 2. Use Result pattern from voice_agent.py

Reuse the `Ok`/`Err` pattern already in the codebase (voice_agent.py:45-61):

```python
from agent.voice_agent import Ok, Err, Result
```

### 3. Create flat retry helper

Add `_run_cli_with_retry()` that returns `Result`:

```python
async def _run_cli_with_retry(self, cli_args: list[str]) -> Result[dict | list]:
    """Run CLI command with LLM-assisted retry on failure."""
    cli_help = await self._cli.get_help()

    for attempt in range(MAX_CLI_RETRIES):
        result = await self._try_cli(cli_args)

        match result:
            case Ok(data):
                return Ok(data)
            case Err(error) if attempt == MAX_CLI_RETRIES - 1:
                return Err(error)
            case Err(error):
                cli_args = await self._fix_cli_args(cli_args, error, cli_help)

    return Err("Max retries exceeded")
```

### 4. Flat CLI execution helper

```python
async def _try_cli(self, cli_args: list[str]) -> Result[dict | list]:
    """Single CLI attempt. Returns Ok(result) or Err(message)."""
    try:
        result = await self._cli.run(*cli_args)
        return Ok(result)
    except Exception as e:
        logger.warning(f"CLI failed: {e}")
        return Err(str(e))
```

### 5. LLM fix helper

```python
async def _fix_cli_args(
    self,
    cli_args: list[str],
    error: str,
    cli_help: str,
) -> list[str]:
    """Ask LLM to fix CLI args based on error. Returns corrected args."""
    # Call LLM with structured output
    # Returns original args if LLM can't fix
```

### 6. Simplify action handlers

QUERY handler becomes:

```python
case Action.QUERY:
    if not output.cli_args:
        return AgentResponse(text=output.response)

    self._last_cli_command = output.cli_args
    result = await self._run_cli_with_retry(output.cli_args)

    match result:
        case Err(error):
            return AgentResponse(text=f"Couldn't fetch tasks: {error}")
        case Ok(data):
            self._last_cli_result = data
            summary = await self._summarize_query_results(data)
            # ... rest of success handling
```

CONFIRM handler becomes:

```python
case Action.CONFIRM:
    if not self._state.pending_command:
        return AgentResponse(text="Nothing to confirm.")

    self._last_cli_command = self._state.pending_command
    result = await self._run_cli_with_retry(self._state.pending_command)
    self._state.pending_command = None

    match result:
        case Err(error):
            return AgentResponse(text=f"Command failed: {error}. What else?")
        case Ok(_):
            return AgentResponse(text=output.response)
```

## Benefits

- **No nested try/except**: Result pattern handles errors as values
- **Flat control flow**: Early returns, no deep nesting
- **Reuses existing pattern**: Consistent with voice_agent.py
- **Single responsibility**: Each helper does one thing

## Risks

- **Slow response**: Retries add latency. Keep max retries low (3).
- **LLM hallucinates fix**: CLI will reject, triggering next retry.

## Open Questions

None - requirements are clear.
