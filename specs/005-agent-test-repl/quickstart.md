# Quickstart: Agent Test REPL

**Feature**: 005-agent-test-repl
**Date**: 2026-01-12

## Prerequisites

1. Python 3.11+ installed
2. Project dependencies installed (`uv sync`)
3. Environment variables configured (`.env` file with LLM API keys)
4. `dimaist-cli` available in PATH (for real CLI operations)

## Running the REPL

```bash
# From repository root
python -m agent.repl

# Or directly
python agent/repl.py
```

## Usage

### Basic Interaction

```
Agent Test REPL
Type messages to interact with TaskAgent. Commands start with /
Type /help for available commands, /exit to quit.

> add task buy groceries
[TaskAgent] I'll add a task for you. Here's what I'm proposing:
  action: propose
  pending: ["task", "add", "buy groceries"]

Should I go ahead and create this task?

> yes
[TaskAgent] Done! Task created successfully.
  action: confirm

> list my tasks
[TaskAgent] Here are your current tasks:
  action: query

1. Buy groceries (due: today)

> /exit
Goodbye!
```

### Available Commands

| Command | Description |
|---------|-------------|
| `/help` | Show available commands and usage |
| `/exit` | Exit the REPL |

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Ctrl+C | Exit the REPL gracefully |
| Ctrl+D | Exit the REPL (EOF) |

## Output Format

Responses show structured information:

```
[AgentName] Response text
  action: <action_type>
  pending: <pending_command if any>
```

**Action Types**:
- `none` - General conversation
- `propose` - Suggesting a command for approval
- `confirm` - Executing approved command
- `cancel` - Cancelled pending command
- `query` - Read-only query executed
- `exit` - Session ending

## Error Handling

Errors are displayed inline without crashing the REPL:

```
> invalid command
[Error] CLIError: Command failed: invalid subcommand

>
```

## Environment Variables

The REPL uses existing environment configuration from `ai/.env`:

| Variable | Description |
|----------|-------------|
| `LLM_BASE_URL` | LLM API endpoint |
| `LLM_API_KEY` | LLM API key |
| `LLM_MODEL` | Model to use |
| `DIMAIST_CLI_PATH` | Path to dimaist-cli (optional, defaults to "dimaist-cli") |

## Troubleshooting

**"CLI not found" error**:
- Ensure `dimaist-cli` is installed and in PATH
- Or set `DIMAIST_CLI_PATH` environment variable

**"LLM call failed" error**:
- Check API key is set correctly
- Verify LLM endpoint is accessible

**No response / hanging**:
- Check network connectivity
- LLM API may be slow or rate-limited
