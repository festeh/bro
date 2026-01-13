# Research: Agent Test REPL

**Feature**: 005-agent-test-repl
**Date**: 2026-01-12

## Overview

This document captures research decisions for implementing the Agent Test REPL - a command-line interface for testing TaskAgent without LiveKit infrastructure.

## Decision 1: Async REPL Pattern

**Decision**: Use `asyncio.run()` with synchronous `input()` in a loop, dispatching to async TaskAgent methods.

**Rationale**:
- Python's `input()` is blocking but simple and reliable
- TaskAgent's `process_message()` is async, so we need asyncio
- Pattern: sync input loop → async processing → sync output
- No external dependencies needed (no `prompt_toolkit` or similar)

**Alternatives Considered**:
- `aioconsole` library: Adds dependency for minimal benefit
- `prompt_toolkit`: Over-engineered for simple REPL
- Threading: Unnecessary complexity

**Implementation**:
```python
async def run_repl():
    agent = TaskAgent(session_id="repl")
    while True:
        user_input = input("> ")  # Blocking but acceptable
        response = await agent.process_message(user_input)
        print(format_response(response))
```

## Decision 2: Output Format

**Decision**: Plain text with structured labels using simple prefixes.

**Rationale**:
- Matches clarification: "Plain text with structured labels (active agent, response type, action metadata)"
- No color dependencies (works in any terminal)
- Easy to parse visually

**Format**:
```
[TaskAgent] response
  action: propose
  pending: ["task", "add", "buy groceries"]
```

**Alternatives Considered**:
- JSON output: Less readable for interactive use
- Rich/colored output: Adds dependency, not needed for dev tool
- Table format: Overkill for simple responses

## Decision 3: REPL Commands

**Decision**: Simple prefix-based commands (`/help`, `/exit`).

**Rationale**:
- Matches clarification: "Minimal set - `/help` and `/exit` only"
- Clear distinction from messages sent to agent
- Standard REPL convention

**Implementation**:
```python
if user_input.startswith("/"):
    handle_command(user_input)
else:
    await agent.process_message(user_input)
```

## Decision 4: Error Handling

**Decision**: Catch exceptions, display friendly message, continue REPL loop.

**Rationale**:
- FR-008: "System MUST display clear error messages"
- Don't crash on LLM/CLI failures
- Allow developer to retry or exit gracefully

**Implementation**:
```python
try:
    response = await agent.process_message(user_input)
except Exception as e:
    print(f"[Error] {type(e).__name__}: {e}")
    continue
```

## Decision 5: Entry Point

**Decision**: Add `if __name__ == "__main__"` block to `repl.py` for direct execution.

**Rationale**:
- Simple: `python -m agent.repl` or `python agent/repl.py`
- No CLI framework needed (no argparse, click, typer)
- Matches existing project patterns

## Dependencies

No new dependencies required. Uses:
- `asyncio` (stdlib)
- `agent.task_agent.TaskAgent` (existing)
- `agent.dimaist_cli.DimaistCLI` (existing, via TaskAgent)

## Open Questions

None - all technical decisions resolved.
