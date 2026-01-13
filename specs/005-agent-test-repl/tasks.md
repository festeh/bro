# Tasks: Agent Test REPL

**Input**: Design documents from `/specs/005-agent-test-repl/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Not explicitly requested - skipping test tasks per spec.

**Organization**: Tasks are grouped by user story. Only User Story 1 (P1) is in scope - User Story 2 is deferred.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1)
- Include exact file paths in descriptions

## Path Conventions

- **Project structure**: `agent/` package at repository root (existing)
- New file: `agent/repl.py`

---

## Phase 1: Setup

**Purpose**: Verify prerequisites and project structure

- [x] T001 Verify existing TaskAgent and DimaistCLI work correctly by running existing tests in agent/tests/

**Checkpoint**: Existing agent infrastructure confirmed working

---

## Phase 2: User Story 1 - Interactive Message Testing (Priority: P1) 🎯 MVP

**Goal**: Developer can test TaskAgent responses via command-line without LiveKit setup

**Independent Test**: Start REPL, type "add task buy milk", verify agent responds with proposal

### Implementation for User Story 1

- [x] T002 [US1] Create REPL module skeleton with main entry point in agent/repl.py
- [x] T003 [US1] Implement async REPL loop with input() and asyncio.run() in agent/repl.py
- [x] T004 [US1] Implement response formatter showing agent name, action type, and metadata in agent/repl.py
- [x] T005 [US1] Implement /help command handler in agent/repl.py
- [x] T006 [US1] Implement /exit command handler in agent/repl.py
- [x] T007 [US1] Add graceful Ctrl+C (KeyboardInterrupt) handling in agent/repl.py
- [x] T008 [US1] Add error handling for LLM and CLI failures with friendly messages in agent/repl.py
- [x] T009 [US1] Add "Processing..." indicator while agent is thinking in agent/repl.py
- [x] T010 [US1] Add startup banner and usage instructions in agent/repl.py

**Checkpoint**: REPL fully functional - can interact with TaskAgent via command line

---

## Phase 3: Polish & Validation

**Purpose**: Final validation and cleanup

- [x] T011 Run REPL manually and verify all acceptance scenarios from spec.md
- [x] T012 Run ruff check on agent/repl.py to ensure code style compliance
- [x] T013 Run ty type checker on agent/repl.py to verify type safety
- [x] T014 Validate quickstart.md instructions by following them step-by-step

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - verify existing code works
- **User Story 1 (Phase 2)**: Depends on Setup - core REPL implementation
- **Polish (Phase 3)**: Depends on User Story 1 completion

### Within User Story 1

```
T002 (skeleton)
  └── T003 (async loop)
        └── T004 (formatter)
        └── T005 (help) ──┐
        └── T006 (exit) ──┼── can be parallel after T003
        └── T007 (Ctrl+C)─┘
        └── T008 (errors)
        └── T009 (indicator)
        └── T010 (banner)
```

### Parallel Opportunities

Within Phase 2, after T003 (async loop) is complete:
- T005 (/help) and T006 (/exit) can be implemented in parallel
- T007 (Ctrl+C), T008 (errors), T009 (indicator), T010 (banner) are independent additions

---

## Parallel Example: User Story 1

```bash
# After T003 (async loop) is complete, these can run in parallel:
Task: "Implement /help command handler in agent/repl.py"
Task: "Implement /exit command handler in agent/repl.py"
Task: "Add graceful Ctrl+C handling in agent/repl.py"
```

---

## Implementation Strategy

### MVP (All in User Story 1)

1. Complete T001: Verify existing tests pass
2. Complete T002-T010: Build REPL incrementally
3. **STOP and VALIDATE**: Test all acceptance scenarios manually
4. Complete T011-T014: Polish and validation

### Single Developer Flow

Execute sequentially: T001 → T002 → T003 → T004 → T005 → T006 → T007 → T008 → T009 → T010 → T011 → T012 → T013 → T014

### Estimated Complexity

- **Total tasks**: 14
- **US1 tasks**: 9 (T002-T010)
- **Low complexity**: Single file implementation, no new dependencies
- **Parallel opportunities**: 3-4 tasks after T003

---

## Notes

- All US1 implementation is in a single file: `agent/repl.py`
- No new dependencies required (uses stdlib asyncio)
- User Story 2 (State Inspection) is deferred - not included in this task list
- Commit after each task or logical group (T002-T003 together, T005-T006 together, etc.)
