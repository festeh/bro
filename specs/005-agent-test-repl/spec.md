# Feature Specification: Agent Test REPL

**Feature Branch**: `005-agent-test-repl`
**Created**: 2026-01-12
**Status**: Draft
**Input**: User description: "let's add a repl for agent for testing"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Interactive Message Testing (Priority: P1)

A developer wants to test the TaskAgent's response to various user messages without setting up LiveKit infrastructure or voice input. They start the REPL, type messages as if they were a user, and see the agent's responses displayed immediately.

**Why this priority**: This is the core use case - enabling rapid iteration and testing of agent behavior without the overhead of the full voice pipeline. Essential for development workflow.

**Independent Test**: Can be fully tested by starting the REPL, typing a message like "add task buy milk", and verifying the agent responds with a proposal. Delivers immediate value for agent development.

**Acceptance Scenarios**:

1. **Given** the REPL is started, **When** the developer types "add task buy groceries", **Then** the agent responds with a proposed command and asks for confirmation
2. **Given** the REPL is running with a pending command, **When** the developer types "yes" or "confirm", **Then** the command is executed (or simulated) and the result is shown
3. **Given** the REPL is running, **When** the developer types "exit" or presses Ctrl+C, **Then** the REPL exits gracefully

---

### User Story 2 - State Inspection During Testing (Priority: P2) *(Deferred)*

A developer wants to inspect the internal state of the TaskAgent during a conversation to debug behavior. They can view pending commands, conversation history, and agent configuration at any point.

**Why this priority**: Critical for debugging agent behavior and understanding why the agent made certain decisions. Supports troubleshooting during development.

**Deferred Reason**: Minimal REPL command set chosen for MVP. State inspection can be added in a future iteration via `/state` and `/history` commands.

**Independent Test**: Can be tested by running a few messages, then using an inspection command (e.g., "/state" or "/history") to view current agent state.

**Acceptance Scenarios**:

1. **Given** the REPL is running with a pending command, **When** the developer types a state inspection command, **Then** the pending command details are displayed
2. **Given** a conversation has occurred, **When** the developer requests history, **Then** all messages and agent decisions are shown chronologically

---

### Edge Cases

- What happens when the LLM service is unavailable? (Graceful error message, ability to retry)
- How does the REPL handle multi-line input if needed? (Single-line input is sufficient for MVP)
- What happens if the user types while agent is still processing? (Input is queued until processing completes)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide an interactive command-line interface that accepts text input and displays agent responses
- **FR-002**: System MUST maintain conversation state across multiple message exchanges within a session
- **FR-003**: Users MUST be able to exit the REPL gracefully via command or keyboard interrupt
- **FR-004**: System MUST display agent responses in plain text with structured labels showing: active agent name, response type (text/action/error), and action metadata (e.g., pending CLI command, action type)
- **FR-005**: System MUST support `/help` (show available commands and usage) and `/exit` (terminate REPL) commands
- **FR-006**: *(Deferred)* System MUST allow inspection of current agent state including pending commands and session info
- **FR-007**: *(Deferred)* System MUST allow viewing conversation history within the current session
- **FR-008**: System MUST display clear error messages when LLM calls or CLI operations fail
- **FR-009**: System MUST show visual indication when the agent is processing a request

### Key Entities

- **Session**: Represents a single REPL testing session with its own conversation history and agent state
- **Message**: A user input or agent response within the conversation, including role and content
- **REPL Command**: A control command (prefixed with "/") that controls REPL behavior rather than being sent to the agent

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Developers can start the REPL and send their first message within 5 seconds of launch
- **SC-002**: Agent responses are displayed within 3 seconds of message submission under normal conditions
- **SC-003**: 100% of core TaskAgent functionality is testable through the REPL without LiveKit setup
- **SC-004**: *(Deferred)* Developers can identify agent state issues within 30 seconds using inspection commands

## Clarifications

### Session 2026-01-12

- Q: Should sessions persist across REPL restarts? → A: Ephemeral only - sessions exist in memory, lost on exit
- Q: Which REPL commands are required? → A: Minimal set - `/help` and `/exit` only
- Q: What output format for agent responses? → A: Plain text with structured labels (active agent, response type, action metadata)
- Q: Should mock CLI mode be included? → A: No - full batteries REPL with real CLI integration only

## Assumptions

- Sessions are ephemeral and exist only in memory; conversation state is lost when the REPL exits
- The REPL will use the existing TaskAgent class without modifications to its core logic
- LLM configuration (API keys, endpoints) will be read from existing environment variables
- The REPL is intended for development/testing purposes, not production use
- Standard terminal capabilities (stdin/stdout) are available
- The existing async agent architecture will be maintained
