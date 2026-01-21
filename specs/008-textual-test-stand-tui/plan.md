# Plan: Agent Test Stand TUI

**Spec**: specs/008-textual-test-stand-tui/spec.md

## Tech Stack

- Language: Python 3.11+
- Framework: Textual (new dependency)
- Storage: None (in-memory state, logs to file)
- Testing: pytest with textual's pilot testing

## Structure

```
agent/
├── teststand/
│   ├── __init__.py
│   ├── app.py           # Main Textual app, layout, key bindings
│   ├── widgets.py       # Custom widgets (ChatPanel, LogPanel, ParamsPanel)
│   ├── models.py        # Merged model list from all providers
│   └── logging.py       # File logging setup for /tmp/bro-logs/teststand.log
├── __main__.py          # Update to support teststand mode
```

## Approach

### Layout

1. **Three-panel layout (60/25/15)**
   Use Textual Grid with `grid-columns: 60% 25% 15%`. Main panel contains chat log + input. Middle panel tails log file. Right panel shows params.

2. **Conversation panel**
   Use `RichLog` widget for scrollable history. Show user input, then `[Intent]`, `[Router]`, `[Response]` lines with color coding. Input at bottom via `Input` widget.

3. **Log panel tails file**
   Configure structlog to write to `/tmp/bro-logs/teststand.log`. Use `aiofiles` or async file watcher to tail the file. Display in `RichLog` widget with auto-scroll.

4. **Parameters panel**
   `Static` widget displaying:
   - Model: `groq/llama-3.3-70b` (provider/model format)
   - Session: `abc123`
   - Active: `Yes/No`
   - Pending: `task complete 42` or `None`

### Interaction

5. **Model cycling (Ctrl+M)**
   Build merged model list from `voice_agent.LLM_MODELS` + `config.get_provider_config()` defaults. Store current index, cycle on Ctrl+M, update TaskAgent's provider/model.

6. **Pending confirm/decline (Y/N keys)**
   When `agent.has_pending` is true, show confirm/decline buttons in conversation. Y/N keys call `agent.confirm()` or `agent.decline()`. Buttons do the same on click.

7. **Retry on error**
   Store last user message. On error, show "Retry" button. Click re-sends the message.

8. **Clear all (Ctrl+L)**
   Clear conversation RichLog, truncate log file, create new TaskAgent session.

9. **Help overlay (Ctrl+H)**
   Show modal with keyboard shortcuts. Dismiss with Escape or Ctrl+H again.

### Async

10. **UI stays responsive**
    Use Textual's `@work` decorator for `process_input()` calls. Worker runs in background, posts messages to update UI on completion.

### Logging

11. **File logging setup**
    Modify `setup_logging()` to accept optional `log_file` path. When set, configure structlog to write to file instead of stdout. Test stand passes `/tmp/bro-logs/teststand.log`.

