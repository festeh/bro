# Feature Specification: Agent Intent Classification

**Feature Branch**: `001-agent-intent-classification`
**Created**: 2026-01-09
**Status**: Draft
**Input**: User description: "We want to enhance our agent. Namely it should add a classification step. It could either do a web search or respond or end dialog based on user input"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Direct Conversational Response (Priority: P1)

A user engages with the agent in casual conversation or asks a general knowledge question. The agent classifies this as a direct response intent and answers immediately using its built-in knowledge, without triggering external searches.

**Why this priority**: This is the most common interaction pattern. Users expect quick, direct responses for general questions and conversation. This establishes the baseline agent behavior that all other intents build upon.

**Independent Test**: Can be fully tested by sending conversational messages ("Hello, how are you?", "What is the capital of France?") and verifying the agent responds directly without delays from external lookups.

**Acceptance Scenarios**:

1. **Given** a user is connected to the agent, **When** they say "Hello, how are you today?", **Then** the agent responds conversationally within 2 seconds without external lookups
2. **Given** a user asks a general knowledge question, **When** they say "What year did World War II end?", **Then** the agent provides an immediate response from its built-in knowledge
3. **Given** a user sends a follow-up question in context, **When** they ask "Tell me more about that", **Then** the agent continues the conversation naturally using prior context

---

### User Story 2 - Web Search for Current Information (Priority: P2)

A user asks about recent events, current prices, live data, or anything requiring up-to-date information the agent cannot know from training. The agent classifies this as a web search intent, performs a search, and synthesizes the results into a helpful response.

**Why this priority**: Web search capability significantly expands the agent's utility by providing access to current information. This transforms the agent from a static knowledge base into a dynamic assistant.

**Independent Test**: Can be fully tested by asking about current events, stock prices, or recent news and verifying the agent performs a search and incorporates external data in its response.

**Acceptance Scenarios**:

1. **Given** a user asks about current events, **When** they say "What happened in the news today?", **Then** the agent performs a web search and summarizes recent news
2. **Given** a user asks about real-time data, **When** they ask "What is the current weather in London?", **Then** the agent retrieves and presents current weather information
3. **Given** a user needs recent information, **When** they ask "Who won the latest NBA game?", **Then** the agent searches for and provides the most recent game results
4. **Given** a search returns no relevant results, **When** the query is too vague or nonsensical, **Then** the agent informs the user and asks for clarification

---

### User Story 3 - End Dialog Gracefully (Priority: P3)

A user indicates they want to end the conversation through explicit farewell, dismissal, or completion signals. The agent recognizes this intent and provides an appropriate closing response, making the user feel the interaction concluded naturally.

**Why this priority**: Clean conversation endings improve user experience and prevent the agent from continuing to respond when the user is done. This is lower priority as conversations often end naturally without explicit classification.

**Independent Test**: Can be fully tested by sending farewell messages ("Goodbye", "Thanks, that's all") and verifying the agent provides a closing response and does not continue prompting.

**Acceptance Scenarios**:

1. **Given** a user says farewell, **When** they say "Goodbye" or "See you later", **Then** the agent responds with an appropriate farewell and marks the conversation as concluded
2. **Given** a user indicates completion, **When** they say "That's all I needed, thanks", **Then** the agent acknowledges completion without asking follow-up questions
3. **Given** a user dismisses the agent, **When** they say "Stop" or "End conversation", **Then** the agent immediately ceases and confirms the conversation has ended

---

### Edge Cases

- What happens when the user's message is ambiguous between intents (e.g., "Search for why the sky is blue")? The agent should make a reasonable choice and proceed (favor direct response for well-known facts, search for less common queries).
- How does the system handle network failures during web search? The agent should inform the user the search failed and offer to try again or answer from available knowledge.
- What happens when a user says "goodbye" but immediately asks another question? The agent should treat the new question as starting a new turn and respond appropriately.
- How does the system handle very short or single-word inputs like "Hi" or "Search"? The agent should use context and reasonable defaults (greetings get direct response, "search" alone prompts for what to search).
- What happens when classification confidence is low? The agent should default to direct response and be ready to pivot if the user indicates they wanted something different.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST classify each user message into one of three intents: direct response, web search, or end dialog
- **FR-002**: System MUST perform classification before generating any response to the user
- **FR-003**: System MUST route web search intents to a search capability and synthesize results into a natural conversational response (not raw result lists)
- **FR-004**: System MUST generate direct responses without external lookups when classified as conversational/knowledge intent
- **FR-005**: System MUST recognize end dialog intent, provide appropriate closing response, and emit a "conversation_ended" event to the frontend
- **FR-006**: System MUST maintain conversation context across multiple turns regardless of intent classification
- **FR-007**: System MUST handle classification failures gracefully by defaulting to direct response
- **FR-008**: System MUST complete classification quickly enough that users do not perceive significant delay
- **FR-009**: System MUST support both text chat and voice agent interfaces with the same classification logic
- **FR-010**: System MUST log all classification decisions including: intent category, confidence score, and input summary for accuracy measurement and debugging

### Key Entities

- **User Message**: The input text or transcribed speech from the user that requires classification
- **Intent Classification**: The determined category (direct response, web search, end dialog) with associated confidence
- **Conversation Context**: The accumulated history of messages in the current session, used to inform classification. Session lifecycle is explicit: a new session begins only when the user starts a new thread/connection (no time-based expiration)
- **Search Query**: The extracted or reformulated search terms when web search intent is detected
- **Agent Response**: The final output delivered to the user after processing based on classified intent

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Agent correctly classifies user intents with at least 85% accuracy across all three categories
- **SC-002**: Users receive responses within 3 seconds for direct response intents (excluding network latency)
- **SC-003**: Web search responses include relevant, current information for time-sensitive queries 90% of the time
- **SC-004**: Users successfully end conversations on first attempt when using common farewell phrases 95% of the time
- **SC-005**: Classification adds no more than 500ms to the overall response time as perceived by users
- **SC-006**: System gracefully handles 100% of classification edge cases without errors or crashes

## Clarifications

### Session 2026-01-09

- Q: How should the intent classification be performed? → A: Single LLM call with structured output (classify + respond in one request)
- Q: Should the system log classification decisions for debugging and accuracy measurement? → A: Log all classifications with intent, confidence, and input summary
- Q: What defines a new conversation session vs. continuing an existing one? → A: Explicit - new session only when user starts new thread/connection
- Q: How should web search results be presented to the user? → A: Synthesize search results into a natural conversational response
- Q: When "end dialog" intent is detected, what should happen after the farewell response? → A: Signal frontend - send farewell + emit "conversation_ended" event

## Assumptions

- Classification will be performed in a single LLM call that outputs both the intent category and the response, minimizing latency
- The existing agent infrastructure (LangGraph for chat, LiveKit for voice) will be extended rather than replaced
- Web search will use an external search provider (implementation detail to be determined in planning phase)
- Classification can be performed using the existing LLM capabilities without requiring a separate specialized model
- Conversation context from the current session is available and can be used to improve classification accuracy
- Both voice and text modalities will share the same classification logic after text extraction
