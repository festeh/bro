# Tasks: Dimaist CLI Integration

**Input**: Design documents from `/specs/004-dimaist-cli-integration/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2)
- Include exact file paths in descriptions

## Path Conventions

Based on plan.md:
- Agent code: `agent/`
- AI/Graph code: `ai/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [ ] T001 Create agent/dimaist_cli.py with DimaistCLI class skeleton and type definitions
- [ ] T002 Create agent/task_agent.py with TaskAgent class skeleton and AgentResponse type
- [ ] T003 [P] Add task agent constants to agent/constants.py (CLI path, timeout, confirmation keywords)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**CRITICAL**: No user story work can begin until this phase is complete

- [ ] T004 Add TASK_MANAGEMENT intent to ai/models.py IntentClassification enum
- [ ] T005 Update intent classification prompt in ai/graph.py to recognize task-related utterances
- [ ] T006 Implement DimaistCLI.run_cli() async subprocess execution in agent/dimaist_cli.py
- [ ] T007 [P] Implement DimaistCLI.list_tasks() in agent/dimaist_cli.py
- [ ] T008 [P] Implement DimaistCLI.list_projects() in agent/dimaist_cli.py
- [ ] T009 [P] Implement DimaistCLI.get_task() in agent/dimaist_cli.py
- [ ] T010 Implement CLI error handling (CLIError, CLINotFoundError, TaskNotFoundError) in agent/dimaist_cli.py
- [ ] T011 Implement TaskAgent.__init__() with LangGraph app, session_id, timezone in agent/task_agent.py
- [ ] T012 Implement TaskAgent date/time properties (current_datetime, today) in agent/task_agent.py
- [ ] T013 Implement TaskAgent._build_system_prompt() with date/time context in agent/task_agent.py
- [ ] T014 Implement TaskAgent state management (TaskAgentState, PendingAction) in agent/task_agent.py
- [ ] T015 Add task_management intent routing in agent/voice_agent.py ChatAgent.handle_user_message()

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 - Multi-Turn Task Creation (Priority: P1) MVP

**Goal**: Users can create tasks through conversational flow with clarification and approval

**Independent Test**: Initiate task creation that requires clarification, provide clarification, approve, verify task created

### Implementation for User Story 1

- [ ] T016 [US1] Implement DimaistCLI.create_task() with title, due_date, project_id in agent/dimaist_cli.py
- [ ] T017 [US1] Implement TaskAgent.process_message() core loop in agent/task_agent.py
- [ ] T018 [US1] Implement TaskAgent._parse_create_intent() to extract task details from user message in agent/task_agent.py
- [ ] T019 [US1] Implement TaskAgent._propose_action() for PendingAction creation in agent/task_agent.py
- [ ] T020 [US1] Implement TaskAgent._handle_confirmation() for yes/no/modify responses in agent/task_agent.py
- [ ] T021 [US1] Implement TaskAgent._execute_pending_action() to run CLI commands in agent/task_agent.py
- [ ] T022 [US1] Implement TaskAgent.start_session() and end_session() lifecycle in agent/task_agent.py
- [ ] T023 [US1] Add structured logging for task_agent_session_start/end, task_agent_action events in agent/task_agent.py

**Checkpoint**: Users can create tasks via voice with approval flow

---

## Phase 4: User Story 2 - Multi-Step Task Operations (Priority: P1)

**Goal**: Users can perform complex operations (query then act) within single session

**Independent Test**: Ask "What's overdue?", then say "Complete the first one", verify both query and completion work

### Implementation for User Story 2

- [ ] T024 [US2] Implement DimaistCLI.complete_task() in agent/dimaist_cli.py
- [ ] T025 [US2] Implement DimaistCLI.update_task() in agent/dimaist_cli.py
- [ ] T026 [US2] Implement DimaistCLI.delete_task() in agent/dimaist_cli.py
- [ ] T027 [US2] Implement TaskAgent._handle_query() for task list queries in agent/task_agent.py
- [ ] T028 [US2] Implement TaskAgent._cache_query_results() to store last query for reference in agent/task_agent.py
- [ ] T029 [US2] Implement TaskAgent._resolve_task_reference() for "the first one", "the milk task" etc in agent/task_agent.py
- [ ] T030 [US2] Implement TaskAgent._parse_complete_intent() in agent/task_agent.py
- [ ] T031 [US2] Implement TaskAgent._parse_update_intent() in agent/task_agent.py
- [ ] T032 [US2] Add task_agent_cli_call logging with command and duration in agent/task_agent.py

**Checkpoint**: Users can query tasks, then act on results within same session

---

## Phase 5: User Story 3 - Disambiguation and Error Recovery (Priority: P2)

**Goal**: System asks for clarification on ambiguous requests and handles errors gracefully

**Independent Test**: Say "Complete the review task" when multiple match, verify system asks which one

### Implementation for User Story 3

- [ ] T033 [US3] Implement TaskAgent._find_matching_tasks() with fuzzy search in agent/task_agent.py
- [ ] T034 [US3] Implement TaskAgent._handle_ambiguous_match() to present options in agent/task_agent.py
- [ ] T035 [US3] Implement TaskAgent._handle_user_selection() for numbered choice responses in agent/task_agent.py
- [ ] T036 [US3] Implement TaskAgent._handle_cli_error() with user-friendly messages in agent/task_agent.py
- [ ] T037 [US3] Implement TaskAgent._suggest_alternatives() for "did you mean X?" suggestions in agent/task_agent.py
- [ ] T038 [US3] Add task_agent_error logging with error type and message in agent/task_agent.py

**Checkpoint**: Users get helpful prompts on ambiguity and clear error messages

---

## Phase 6: User Story 4 - Quick Approval Flow (Priority: P3)

**Goal**: Unambiguous requests get fast, streamlined approval prompts

**Independent Test**: Say "Add task: buy milk tomorrow", approve with "yes", verify fast creation

### Implementation for User Story 4

- [ ] T039 [US4] Implement TaskAgent._is_complete_request() to detect fully-specified intents in agent/task_agent.py
- [ ] T040 [US4] Implement TaskAgent._generate_concise_confirmation() for quick approval prompts in agent/task_agent.py
- [ ] T041 [US4] Implement TaskAgent._is_read_only_query() to bypass approval for queries in agent/task_agent.py
- [ ] T042 [US4] Optimize TaskAgent response latency by minimizing LLM calls for simple operations in agent/task_agent.py

**Checkpoint**: Simple requests complete quickly with minimal friction

---

## Phase 7: User Story 5 - Natural Language Task Management (Priority: P4)

**Goal**: Users can speak naturally without memorizing commands

**Independent Test**: Say "I need to remember to send the report by end of week", verify task created

### Implementation for User Story 5

- [ ] T043 [US5] Enhance TaskAgent._build_system_prompt() with natural language interpretation examples in agent/task_agent.py
- [ ] T044 [US5] Implement TaskAgent._parse_natural_task_intent() for varied phrasings in agent/task_agent.py
- [ ] T045 [US5] Implement TaskAgent._parse_completion_phrases() for "I finished X", "X is done" in agent/task_agent.py
- [ ] T046 [US5] Implement TaskAgent._generate_task_summary() for "how busy am I" queries in agent/task_agent.py
- [ ] T047 [US5] Add natural language date context with day-of-week awareness in agent/task_agent.py

**Checkpoint**: Users can manage tasks using natural conversational language

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T048 [P] Implement TaskAgent._detect_exit_intent() for topic change detection in agent/task_agent.py
- [ ] T049 [P] Implement TaskAgent._handle_abandonment() for graceful exit on "never mind" in agent/task_agent.py
- [ ] T050 [P] Add CLI availability check on agent startup in agent/voice_agent.py
- [ ] T051 Implement TaskAgent.is_active and has_pending_action properties in agent/task_agent.py
- [ ] T052 Run type checker (ty check) on all new files
- [ ] T053 Run linter (ruff check) on all new files
- [ ] T054 Validate against quickstart.md test scenarios

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
  - US1 and US2 are both P1 priority, can proceed in parallel
  - US3 (P2) can start after Foundational
  - US4 (P3) and US5 (P4) can start after Foundational
- **Polish (Phase 8)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational - No dependencies on other stories
- **User Story 2 (P1)**: Can start after Foundational - Independent of US1 but benefits from US1 approval flow (shared code)
- **User Story 3 (P2)**: Can start after Foundational - Adds disambiguation to US1/US2 flows
- **User Story 4 (P3)**: Can start after US1 - Optimizes the approval flow
- **User Story 5 (P4)**: Can start after Foundational - Enhances natural language handling

### Within Each User Story

- CLI methods before agent methods that use them
- Core implementation before edge cases
- Logging added with each feature

### Parallel Opportunities

- T003 (constants) can run in parallel with T001/T002
- T007, T008, T009 (CLI read methods) can run in parallel after T006
- T024, T025, T026 (CLI write methods) can run in parallel
- T048, T049, T050 (polish) can run in parallel

---

## Parallel Example: Foundational Phase

```bash
# After T006 completes, launch CLI read methods together:
Task: "Implement DimaistCLI.list_tasks() in agent/dimaist_cli.py"
Task: "Implement DimaistCLI.list_projects() in agent/dimaist_cli.py"
Task: "Implement DimaistCLI.get_task() in agent/dimaist_cli.py"
```

## Parallel Example: User Story 2

```bash
# CLI write methods can run in parallel:
Task: "Implement DimaistCLI.complete_task() in agent/dimaist_cli.py"
Task: "Implement DimaistCLI.update_task() in agent/dimaist_cli.py"
Task: "Implement DimaistCLI.delete_task() in agent/dimaist_cli.py"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1 (task creation with approval)
4. **STOP and VALIDATE**: Test task creation via voice
5. Deploy/demo if ready

### Incremental Delivery

1. Setup + Foundational Complete
2. Add User Story 1 (create) + User Story 2 (query/complete) MVP!
3. Add User Story 3 (disambiguation) Improved UX
4. Add User Story 4 (quick approval) Polish
5. Add User Story 5 (natural language) Enhanced
6. Each story adds value without breaking previous stories

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- All CLI methods output JSON, errors to stderr
- TaskAgent uses existing LangGraph app for state persistence
