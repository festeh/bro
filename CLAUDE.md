# bro Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-01-10

## Active Technologies
- Python 3.11+ (matching existing agent codebase) + livekit-agents (existing), asyncio subprocess for CLI execution (004-dimaist-cli-integration)
- N/A (Dimaist manages its own PostgreSQL; bro only invokes CLI) (004-dimaist-cli-integration)
- Python 3.11+ (matches existing codebase) + asyncio (existing), pydantic (existing), langchain-openai (existing via TaskAgent) (005-agent-test-repl)
- N/A (sessions are ephemeral, in-memory only) (005-agent-test-repl)

- Python 3.11+ + ruff (linter/formatter), ty (type checker) (003-python-type-safety)

## Project Structure

```text
src/
tests/
```

## Commands

cd src [ONLY COMMANDS FOR ACTIVE TECHNOLOGIES][ONLY COMMANDS FOR ACTIVE TECHNOLOGIES] pytest [ONLY COMMANDS FOR ACTIVE TECHNOLOGIES][ONLY COMMANDS FOR ACTIVE TECHNOLOGIES] ruff check .

## Code Style

Python 3.11+: Follow standard conventions

## Recent Changes
- 005-agent-test-repl: Added Python 3.11+ (matches existing codebase) + asyncio (existing), pydantic (existing), langchain-openai (existing via TaskAgent)
- 004-dimaist-cli-integration: Added Python 3.11+ (matching existing agent codebase) + livekit-agents (existing), asyncio subprocess for CLI execution

- 003-python-type-safety: Added Python 3.11+ + ruff (linter/formatter), ty (type checker)

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
