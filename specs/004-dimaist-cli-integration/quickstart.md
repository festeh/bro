# Quickstart: Dimaist CLI Integration

**Date**: 2026-01-10
**Feature**: 004-dimaist-cli-integration

## Prerequisites

1. **Dimaist CLI installed and in PATH**
   ```bash
   # Verify CLI is available
   which dimaist-cli
   # Or check version
   dimaist-cli --help
   ```

2. **Database connection configured**
   ```bash
   # Ensure DATABASE_URL is set (same as dimaist backend)
   export DATABASE_URL="postgres://user:pass@localhost:5432/dimaist"
   # Or in .env file in bro root
   ```

3. **Bro agent running**
   ```bash
   cd /home/dima/projects/bro/agent
   uv run python voice_agent.py dev
   ```

## Testing the Integration

### 1. Start a Voice Session

Connect via LiveKit client (desktop app, phone, or wear) and enable microphone.

### 2. Test Task Queries (Read-Only)

These should work immediately without confirmation:

```
You: "What tasks do I have today?"
Bro: "You have 3 tasks today: buy groceries, call dentist, and review PR."

You: "What's overdue?"
Bro: "You have 1 overdue task: finish report, due yesterday."

You: "Show me my work project tasks"
Bro: "Your work project has 5 tasks: ..."
```

### 3. Test Task Creation (Requires Approval)

```
You: "Add a task to buy milk tomorrow"
Bro: "Create task 'buy milk' due tomorrow?"
You: "Yes"
Bro: "Done. Task created."

You: "Add task: review pull request by Friday in work project"
Bro: "Create task 'review pull request' due Friday in work?"
You: "Actually make it Thursday"
Bro: "Create task 'review pull request' due Thursday in work?"
You: "Confirm"
Bro: "Done. Task created."
```

### 4. Test Task Completion (Requires Approval)

```
You: "Complete the milk task"
Bro: "Complete 'buy milk'?"
You: "Yes"
Bro: "Done. Task completed."

You: "Mark the review task as done"
Bro: "I found 2 review tasks: review pull request and review budget. Which one?"
You: "The first one"
Bro: "Complete 'review pull request'?"
You: "Go ahead"
Bro: "Done. Task completed."
```

### 5. Test Exit from Task Mode

```
You: "What's the weather like?"  # Non-task intent
Bro: [Returns to main agent, answers weather question]

You: "Never mind"  # Explicit exit
Bro: "Okay, let me know if you need help with tasks."
```

## Troubleshooting

### "Task management is not available"

CLI not found. Check:
```bash
which dimaist-cli
# If not in PATH, set DIMAIST_CLI_PATH in .env
```

### "Cannot connect to task database"

Database connection failed. Check:
```bash
# Verify DATABASE_URL
echo $DATABASE_URL
# Test CLI directly
dimaist-cli task list
```

### Tasks not showing up

Check if Dimaist backend is running and has tasks:
```bash
dimaist-cli task list | jq '.[].title'
```

### Agent not recognizing task intents

Check if intent classification includes task_management:
```python
# In ai/graph.py, verify CLASSIFICATION_SYSTEM_PROMPT includes task_management
```

## Development Commands

```bash
# Run agent in dev mode
cd /home/dima/projects/bro/agent
uv run python voice_agent.py dev

# Run type checker
uv run ty check .

# Run linter
uv run ruff check .

# Test CLI wrapper directly
python -c "
import asyncio
from dimaist_cli import DimaistCLI
async def main():
    cli = DimaistCLI()
    tasks = await cli.list_tasks()
    print(f'Found {len(tasks)} tasks')
asyncio.run(main())
"
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | (required) | PostgreSQL connection for dimaist-cli |
| `DIMAIST_CLI_PATH` | `dimaist-cli` | Path to CLI binary |
| `TASK_AGENT_TIMEOUT` | `30` | CLI command timeout in seconds |

### Agent Settings

Task agent inherits settings from main agent via participant metadata:
```json
{
  "agent_mode": "chat",
  "stt_provider": "deepgram",
  "llm_model": "deepseekV31",
  "tts_enabled": true
}
```
