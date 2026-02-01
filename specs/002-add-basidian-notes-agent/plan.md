# Plan: Basidian Notes Agent

## Tech Stack

- Language: Python
- Framework: Existing agent architecture (LangChain ChatOpenAI + structured output)
- Storage: Basidian REST API via `BasidianClient` (from basidian package)
- Testing: Existing teststand TUI

## Key Design Decision: HTTP Client vs CLI Wrapper

The task agent wraps `dimaist-cli` via subprocess because it outputs JSON. Basidian's `bscli` outputs human-readable text, so wrapping it would require parsing. Instead, we use `BasidianClient` (the async HTTP client from the basidian package) directly. This is simpler and more reliable.

The basidian package is already installable (`pip install -e /home/dima/projects/basidian/backend`). We import `BasidianClient` and the Pydantic models (`FsNode`, `Note`) directly.

## Structure

```
agent/
├── basidian/
│   ├── __init__.py
│   └── basidian_agent.py    # Agent + client usage (no CLI wrapper needed)
├── constants.py              # Add BASIDIAN_URL
├── voice_agent.py            # Add routing for NOTES intent
ai/
├── models.py                 # Add Intent.NOTES
├── graph.py                  # Update classification prompt
```

## Approach

### 1. Add `NOTES` intent to classification

Add `Intent.NOTES` in `ai/models.py`. Update the classification system prompt in `ai/graph.py` to recognize note-related queries: "create a note", "find my notes about X", "what did I write about Y", "show my recent notes", "save this as a note".

### 2. Create `agent/basidian/basidian_agent.py`

Mirror the `TaskAgent` pattern with these differences:

- **No CLI wrapper class.** Use `BasidianClient` directly as an async context manager.
- **Simpler action set.** Notes don't need the propose/confirm flow — reads and writes are both low-risk. Actions: `NONE`, `QUERY`, `WRITE`, `EXIT`.
  - `QUERY`: Read-only operations (search, list, read file, recent)
  - `WRITE`: Create/update/delete notes and files (execute immediately)
  - `NONE`: Conversation, clarification
  - `EXIT`: Return control to main agent
- **Structured output model** (`BasidianAgentOutput`): `response`, `action`, `operation` (enum: search_notes, search_files, get_tree, read_file, create_file, update_file, delete_file, recent), `args` (dict with operation-specific params like `path`, `query`, `content`).
- **System prompt** includes available operations with parameter descriptions instead of CLI help text.
- **Summarize results** using the same LLM summarization pattern for query results.
- **Backend URL** from `BASIDIAN_URL` constant (default `http://localhost:8090`, overridable via env).

### 3. Add constants

In `agent/constants.py`, add:
```python
BASIDIAN_URL = "http://localhost:8090"  # Default, overridable via env
```

### 4. Wire into voice agent

In `agent/voice_agent.py`:
- Import `BasidianAgent`
- Add `_basidian_agent` field alongside `_task_agent`
- Add `_route_to_basidian_agent()` method (same pattern as `_route_to_task_agent`)
- In `_process_input()`, check for `Intent.NOTES` and route accordingly
- Respect `excluded_agents` with `"basidian"` key

### 5. Install basidian as dependency

Add `basidian` package to the project's dependencies so `BasidianClient` is importable:
```
pip install -e /home/dima/projects/basidian/backend
```

## Risks

- **Basidian server not running**: Agent should handle connection errors gracefully and tell the user. `BasidianClient` raises `httpx` errors — catch and return friendly messages.
- **Intent overlap**: "Save this" could be task or notes. The classification prompt needs clear examples to disambiguate. Task management is about todos/deadlines; notes is about saving/searching knowledge.

## Open Questions

- Should we skip the propose/confirm flow entirely for destructive operations (delete)? The task agent requires confirmation for mutations. For notes, we could do the same for deletes only.
