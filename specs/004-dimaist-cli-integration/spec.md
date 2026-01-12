# Feature Specification: Dimaist CLI Integration

**Feature Branch**: `004-dimaist-cli-integration`
**Created**: 2026-01-10
**Status**: Draft
**Input**: User description: "let's integrate with dimaist cli (sources in ~/prjects/dimaist)"

## Core Concept: Agent-Based Sub-Flow

Task management is **not a one-shot operation**. Unlike simple commands that succeed or fail immediately, task management requires:

- **Multi-turn conversations**: The system may need to ask clarifying questions, disambiguate between similar tasks, or gather missing information
- **Iterative refinement**: Users may correct, modify, or expand their initial request across multiple exchanges
- **Multi-step workflows**: A single user intent (e.g., "plan my week") may require multiple operations executed in sequence

To handle this, when the `task_management` intent is detected, bro's main agent spawns a **separate task agent** that:
- Maintains its own conversation context within the parent flow
- Executes Dimaist operations by spawning `dimaist-cli` commands
- Handles disambiguation and error recovery autonomously
- Returns control to the main agent once the user's goal is complete

The main agent delegates to the task agent and relays responses back to the user. The task agent is the only component that directly invokes the Dimaist CLI.

### Date/Time Awareness

The task agent MUST be aware of the current date and time in the user's local timezone. This enables:
- Natural language date parsing ("tomorrow", "next Friday", "in 3 days")
- Relative date queries ("what's due this week", "overdue tasks")
- Contextual responses ("You have 3 tasks due today")

The current date/time is injected into the agent's context at session start and refreshed as needed.

### User Approval for Destructive Actions

**Critical**: The agent MUST NOT execute actions that modify the task database without explicit user approval. This includes:
- **Creating** new tasks
- **Updating** existing tasks (title, due date, project, etc.)
- **Completing** tasks
- **Deleting** tasks

The agent proposes changes and waits for user confirmation before executing. Read-only operations (querying, listing, summarizing) do not require approval. This ensures users remain in control and prevents unintended modifications from misheard commands or AI misinterpretation.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Multi-Turn Task Creation (Priority: P1)

As a user, I want to create tasks through a conversational flow, so that I can refine my request if the system needs more information or misunderstands me.

**Why this priority**: Task creation is fundamental, but real-world usage rarely succeeds on the first attempt. Users provide incomplete info, speak ambiguously, or change their mind mid-request.

**Independent Test**: Can be fully tested by initiating a task creation that requires clarification, providing the clarification, and verifying the task is created correctly.

**Acceptance Scenarios**:

1. **Given** a user says "Add a task for the meeting", **When** the system detects ambiguity (which meeting? when?), **Then** the task agent asks "What's the meeting about and when is it due?" and waits for the user's response before proposing the task.
2. **Given** a user says "Add task: review PR by Friday", **When** the agent has gathered sufficient info, **Then** the agent proposes "Create task 'review PR' due Friday?" and waits for user approval before executing.
3. **Given** a user approves the proposed task, **When** the user says "yes" or "confirm", **Then** the agent creates the task and confirms "Done. Anything else to add, like a project or description?"
4. **Given** a user says "Actually make that Thursday, and put it in the work project", **When** the agent proposes the update, **Then** the user must approve before the agent modifies the task.
5. **Given** a user rejects a proposed action, **When** the user says "no" or "cancel", **Then** the agent does not execute the action and asks how to proceed.
6. **Given** a user provides incomplete information and then abandons the flow, **When** the user says "never mind" or changes topic, **Then** the agent gracefully exits without creating a partial task.

---

### User Story 2 - Multi-Step Task Operations (Priority: P1)

As a user, I want to perform complex task operations that involve multiple steps, so that I can manage my tasks efficiently through a single conversational session.

**Why this priority**: Many real task management needs aren't atomic - they involve querying, then acting, then verifying.

**Independent Test**: Can be fully tested by asking "What's overdue?" then saying "Complete the first one" and verifying both the query and completion work within a single flow.

**Acceptance Scenarios**:

1. **Given** a user asks "What tasks are overdue?", **When** the agent lists 3 overdue tasks, **Then** the user can say "Complete the dentist one" and the agent asks "Complete 'dentist appointment'?" before executing.
2. **Given** a user says "Move all my personal tasks to next week", **When** the agent identifies multiple tasks, **Then** it proposes "I found 5 personal tasks. Move all of them to next Monday?" and waits for user approval before modifying any tasks.
3. **Given** a user says "Help me plan tomorrow", **When** the agent reviews tomorrow's tasks, **Then** it can suggest reordering, ask about priorities, and help reschedule - all within the same sub-flow.

---

### User Story 3 - Disambiguation and Error Recovery (Priority: P2)

As a user, I want the system to ask for clarification when my request is ambiguous rather than guessing wrong or failing silently.

**Why this priority**: Disambiguation is essential for a conversational interface. One-shot systems that guess wrong frustrate users more than systems that ask.

**Independent Test**: Can be fully tested by saying "Complete the review task" when multiple tasks contain "review" and verifying the system asks which one.

**Acceptance Scenarios**:

1. **Given** a user says "Complete the review task" and 3 tasks match, **When** the agent detects ambiguity, **Then** it presents the options: "I found 3 review tasks: (1) Review PR #42, (2) Review budget, (3) Review notes. Which one?"
2. **Given** a user says "Add to project" without specifying which project, **When** the agent needs the project name, **Then** it asks "Which project?" and optionally lists available projects.
3. **Given** Dimaist returns an error (e.g., project not found), **When** the agent receives the error, **Then** it explains the issue to the user and suggests alternatives (e.g., "Project 'wrk' not found. Did you mean 'work'?").

---

### User Story 4 - Quick Approval Flow (Priority: P3)

As a user, when my request is complete and unambiguous, I want the approval step to be quick and straightforward.

**Why this priority**: While approval is always required for modifications, simple cases should minimize friction. The agent should present a clear, concise confirmation.

**Independent Test**: Can be fully tested by saying "Add task: buy milk tomorrow", approving with "yes", and verifying creation.

**Acceptance Scenarios**:

1. **Given** a user provides complete task info "Add task: call dentist tomorrow at 2pm in personal project", **When** no clarification is needed, **Then** the agent immediately proposes "Create 'call dentist' tomorrow 2pm in personal?" for quick approval.
2. **Given** a user asks "What's due today?", **When** the query is unambiguous, **Then** the agent responds with the list immediately (no approval needed for read-only).
3. **Given** a user says "Complete buy groceries", **When** exactly one task matches, **Then** the agent asks "Complete 'buy groceries'?" and executes only after user confirms.

---

### User Story 5 - Natural Language Task Management (Priority: P4)

As a user, I want to speak naturally about my tasks without memorizing commands, and have the AI interpret my intent correctly.

**Why this priority**: Natural language improves usability but requires the core multi-turn infrastructure to be in place first.

**Independent Test**: Can be fully tested by saying "I need to remember to send the report by end of week" and verifying task creation.

**Acceptance Scenarios**:

1. **Given** a user says "Remind me to call the dentist next Monday", **Then** the agent interprets this as task creation with the appropriate due date.
2. **Given** a user asks "How busy am I this week?", **Then** the agent provides a summary of task count and key deadlines.
3. **Given** a user says "I finished the grocery shopping", **Then** the agent interprets this as completing the matching task.

---

### Out of Scope

- Creating, updating, or deleting projects (users can only assign tasks to existing projects)
- Label management (creating, editing, or assigning labels)
- Reminder management
- Task descriptions (title-only for voice simplicity)
- Bulk import/export operations

### Edge Cases

- What happens when Dimaist service is unreachable? The agent informs the user and offers to retry or exit the flow.
- What happens if the user abandons mid-flow? The agent detects topic change or explicit cancellation and exits gracefully without partial state.
- What happens when voice recognition misinterprets the task title? The agent confirms before executing, allowing correction.
- How long does the agent sub-flow stay active? Until the user's goal is complete, they explicitly end it, or they change to a non-task topic.
- What happens if a multi-step operation partially fails? The agent reports what succeeded and what failed, then asks how to proceed.

## Requirements *(mandatory)*

### Functional Requirements

**Agent Sub-Flow**
- **FR-001**: System MUST spawn an task agent sub-flow when `task_management` intent is detected
- **FR-002**: The agent sub-flow MUST maintain conversation context across multiple turns until the task goal is achieved
- **FR-003**: The agent MUST be able to execute multiple Dimaist operations within a single sub-flow session
- **FR-004**: The agent MUST return control to the main flow when the user's goal is complete or they exit the task context
- **FR-005**: The agent MUST handle graceful exit when user abandons the flow (explicit cancellation or topic change)

**User Approval**
- **FR-006**: The agent MUST request explicit user approval before creating any new task
- **FR-007**: The agent MUST request explicit user approval before updating any existing task
- **FR-008**: The agent MUST request explicit user approval before completing any task
- **FR-009**: The agent MUST request explicit user approval before deleting any task
- **FR-010**: The agent MUST clearly state the proposed action and await user confirmation (e.g., "Create task 'buy groceries' due tomorrow?")
- **FR-011**: The agent MUST NOT execute database-modifying actions without receiving affirmative user response
- **FR-012**: Read-only operations (list, query, summarize) MUST NOT require user approval

**Task Operations**
- **FR-013**: System MUST allow users to create tasks in Dimaist via voice commands
- **FR-014**: System MUST support specifying task titles through natural speech
- **FR-015**: System MUST support specifying due dates using natural language (e.g., "tomorrow", "next Friday", "in 3 days")
- **FR-016**: System MUST support assigning tasks to existing Dimaist projects
- **FR-017**: System MUST allow users to query their task list via voice
- **FR-018**: System MUST support filtering tasks by date range (today, this week, overdue)
- **FR-019**: System MUST support filtering tasks by project name
- **FR-020**: System MUST allow users to mark tasks as complete via voice
- **FR-021**: System MUST handle recurring tasks correctly when marked complete

**Date/Time Context**
- **FR-022**: The task agent MUST be initialized with the current date and time in the user's local timezone
- **FR-023**: The task agent MUST use the local date/time context when parsing natural language dates (e.g., "tomorrow", "next week")

**Conversation Quality**
- **FR-024**: System MUST provide voice confirmation after task operations
- **FR-025**: System MUST request clarification when task references are ambiguous
- **FR-026**: System MUST handle Dimaist errors gracefully with user-friendly messages and recovery suggestions
- **FR-027**: System MUST allow users to modify or correct information provided in previous turns within the same sub-flow
- **FR-028**: System MUST add a new `task_management` intent type to bro's intent classification system

### Key Entities

- **Task**: Represents a task in Dimaist with title, description, due date, project association, completion status, and recurrence pattern
- **Project**: A grouping container for tasks with name and color
- **Main Agent**: Bro's primary conversational agent that handles intent classification and delegates to specialized agents
- **Task Agent**: A separate task agent spawned by the main agent to handle task management; executes `dimaist-cli` commands
- **Task Intent**: The interpreted goal from user speech (create, query, complete, modify, plan)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can complete multi-turn task operations (requiring 2+ exchanges) successfully in 90% of attempts
- **SC-002**: Single-turn operations complete within 10 seconds from utterance to confirmation
- **SC-003**: Disambiguation requests correctly identify the user's intended task in 85% of cases
- **SC-004**: Multi-step workflows (query → act → verify) complete successfully in 80% of attempts
- **SC-005**: System correctly parses natural language dates in 85% of cases
- **SC-006**: Users can complete a full task management workflow (create, view, complete) entirely through voice
- **SC-007**: Agent sub-flow exits gracefully (no orphaned state) in 95% of abandonment scenarios

## Clarifications

### Session 2026-01-10

- Q: How does bro communicate with Dimaist? → A: Separate task agent spawns dimaist-cli commands; bro main agent interacts with this task agent
- Q: What operations are in scope? → A: Task CRUD (create, query, complete, delete) + assigning tasks to existing projects; project creation/deletion and label management are out of scope
- Q: How are tasks matched by name? → A: Task agent decides adaptively (e.g., exact match first, fuzzy search on no results); not a rigid spec constraint

## Assumptions

- Users have an existing Dimaist instance running with tasks and projects configured
- The Dimaist database is accessible from the bro system (same machine or network accessible)
- Voice recognition quality is sufficient to capture task titles (standard STT accuracy applies)
- Users primarily interact with tasks using titles rather than IDs
- Project names are unique and reasonably short for voice interaction
