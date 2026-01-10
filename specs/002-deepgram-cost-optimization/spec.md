# Feature Specification: ASR Cost Optimization

**Feature Branch**: `001-deepgram-cost-optimization`
**Created**: 2026-01-10
**Status**: Draft
**Input**: User description: "Cost optimization for ASR providers. Use VAD to filter silence (without losing speech) and enforce 1-minute turn limit with frontend notification."

## Clarifications

### Session 2026-01-10

- Q: How should frontend notifications for turn warnings/terminations be delivered? → A: Data channel message via existing LiveKit data topics
- Q: What should happen to buffered audio when ASR connection fails during speech? → A: Buffer audio locally (up to 5s), attempt reconnect, then resume or discard with error notification

## User Scenarios & Testing *(mandatory)*

### User Story 1 - VAD-Gated Audio Transmission (Priority: P1)

As a system operator, I want the voice agent to only send audio containing speech to any configured ASR provider, so that we reduce costs by not paying for silence processing regardless of which provider is in use.

**Why this priority**: This is the primary cost driver - currently all audio (including silence) is sent to ASR providers. Filtering silence before transmission directly reduces billable audio duration, which is the main business goal. This applies universally to all ASR providers (Deepgram, ElevenLabs, etc.).

**Independent Test**: Can be fully tested by conducting a voice session with natural pauses and verifying that only speech segments are transmitted, while transcription quality remains unchanged.

**Acceptance Scenarios**:

1. **Given** a user is in a voice session with any ASR provider and speaking, **When** speech is detected, **Then** the audio is transmitted to the ASR provider immediately with no perceptible delay
2. **Given** a user is in a voice session and stops speaking, **When** silence is detected for the configured threshold, **Then** audio transmission pauses until speech resumes
3. **Given** a user pauses briefly mid-sentence (under 500ms), **When** the brief silence occurs, **Then** audio transmission continues without interruption to preserve natural speech patterns
4. **Given** audio is being filtered for silence, **When** any speech occurs, **Then** no speech content is lost or clipped (zero word loss tolerance)
5. **Given** the system switches between ASR providers mid-session, **When** the switch occurs, **Then** VAD filtering continues to work seamlessly with the new provider

---

### User Story 2 - Turn Duration Limit Enforcement (Priority: P2)

As a system operator, I want to automatically end turns that exceed one minute, so that we prevent runaway costs from stuck sessions or unusually long monologues across all ASR providers.

**Why this priority**: While less common than silence, excessively long turns can cause significant unexpected costs. This is a safety mechanism that protects against edge cases and stuck states, independent of which ASR provider is configured.

**Independent Test**: Can be fully tested by starting a voice session and speaking continuously for over one minute, verifying the turn is terminated and frontend is notified.

**Acceptance Scenarios**:

1. **Given** a user is speaking continuously to any ASR provider, **When** the turn duration reaches 60 seconds, **Then** audio transmission to the ASR provider stops
2. **Given** a turn is terminated due to duration limit, **When** the termination occurs, **Then** the frontend receives a notification indicating the reason
3. **Given** a turn was terminated due to duration limit, **When** the user starts speaking again, **Then** a new turn begins normally
4. **Given** a turn is approaching the time limit, **When** the turn reaches 55 seconds, **Then** the frontend receives a warning notification (5-second warning)

---

### User Story 3 - Cost Monitoring Visibility (Priority: P3)

As a system operator, I want to see metrics on how much audio was filtered versus transmitted per ASR provider, so that I can verify the cost savings and monitor system effectiveness across all providers.

**Why this priority**: This provides visibility into the feature's effectiveness and helps identify any issues with the VAD configuration. Important for validation but not critical for the core functionality.

**Independent Test**: Can be fully tested by conducting voice sessions and reviewing logged metrics for filtered vs transmitted audio ratios.

**Acceptance Scenarios**:

1. **Given** a voice session has completed, **When** I review the session metrics, **Then** I can see the total audio duration, transmitted duration, filtered duration, and which ASR provider was used
2. **Given** multiple voice sessions have occurred with different ASR providers, **When** I review aggregate metrics, **Then** I can see the overall percentage of audio filtered per provider (cost savings indicator)

---

### Edge Cases

- What happens when speech detection is uncertain (borderline audio levels)? The system should err on the side of transmission to avoid losing speech.
- What happens during network latency spikes? Audio should be buffered briefly to prevent gaps, but excessive buffering should not occur.
- What happens if the user speaks exactly at the 60-second boundary? The current utterance should be allowed to complete (grace period of up to 2 seconds) before termination.
- What happens if VAD misclassifies speech as silence? The system should use conservative thresholds to minimize false negatives (missed speech) even at the cost of some false positives (transmitted silence).
- What happens if a turn is terminated mid-word? The partial transcript should still be delivered to maintain context.
- What happens if the ASR provider is switched mid-turn? The current turn should complete with the original provider; new turns use the new provider.
- What happens if an ASR provider has its own server-side VAD? The client-side VAD should still apply as a first-pass filter; provider-specific VAD can provide additional processing.
- What happens if the ASR connection drops during active speech? Buffer audio locally for up to 5 seconds while attempting reconnection; if reconnection fails, discard buffer and notify frontend of the error.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST detect voice activity in the audio stream before transmitting to any ASR provider
- **FR-002**: System MUST transmit audio to the ASR provider within 50ms of speech detection onset (no perceptible delay)
- **FR-003**: System MUST NOT transmit audio during periods of confirmed silence (silence threshold: configurable, default 300ms)
- **FR-004**: System MUST NOT lose any speech content due to VAD filtering (zero tolerance for clipped words)
- **FR-005**: System MUST configure Silero VAD's `prefix_padding_duration` to capture speech onset (default 500ms)
- **FR-006**: System MUST terminate turns that exceed 60 seconds of continuous transmission
- **FR-007**: System MUST notify the frontend via LiveKit data topic when a turn is terminated due to duration limit
- **FR-008**: System MUST notify the frontend via LiveKit data topic when a turn is approaching the duration limit (5-second warning at 55 seconds)
- **FR-009**: System MUST allow new turns to begin after a duration-limited turn ends
- **FR-010**: System MUST log metrics for each session: total audio duration, transmitted duration, filtered duration, and ASR provider used
- **FR-011**: System MUST use conservative VAD thresholds that favor false positives (transmitting silence) over false negatives (missing speech)
- **FR-012**: System MUST provide a grace period of up to 2 seconds at turn boundaries to avoid cutting off mid-utterance
- **FR-013**: System MUST apply VAD filtering uniformly across all supported ASR providers (Deepgram, ElevenLabs, and any future providers)
- **FR-014**: System MUST apply turn duration limits uniformly across all supported ASR providers
- **FR-015**: System MUST buffer audio locally for up to 5 seconds during ASR connection failures, attempt reconnection, and resume transmission or discard with frontend error notification if reconnection fails

### Key Entities

- **Voice Session**: A continuous period of voice interaction between user and system; contains multiple turns; associated with an ASR provider
- **Turn**: A single user speaking segment; bounded by speech start and speech end (or timeout)
- **Audio Frame**: A discrete unit of audio data (typically 20-50ms); the unit of VAD analysis
- **VAD State**: Current voice activity status (speaking/silent) with associated confidence level
- **Transmission Window**: Period during which audio is actively sent to ASR; begins at speech onset and ends at silence confirmation or timeout
- **ASR Provider**: The speech recognition service receiving audio (e.g., Deepgram, ElevenLabs); interchangeable at the transmission layer

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Billable audio duration reduced by at least 40% compared to baseline (sending all audio) during typical conversation sessions with natural pauses, across all ASR providers
- **SC-002**: Zero reported instances of lost or clipped speech due to VAD filtering (measured via user feedback and transcript review)
- **SC-003**: Turn termination notifications delivered to frontend within 100ms of the limit being reached
- **SC-004**: 95% of turns complete naturally without hitting the duration limit during normal usage
- **SC-005**: Transcription quality (word accuracy) remains within 2% of baseline (no VAD filtering) as measured by comparing transcripts
- **SC-006**: VAD filtering and turn limits work identically regardless of which ASR provider is configured

## Assumptions

- The existing VAD component in the codebase is suitable for this purpose and provides sufficient accuracy
- Frontend can receive and handle notification messages for turn warnings and terminations via LiveKit data topics
- All ASR providers bill based on transmitted audio duration, making silence filtering directly cost-effective
- Typical conversation sessions include significant silence (pauses between utterances, thinking time) that can be filtered
- A 60-second turn limit is appropriate for the expected use cases; longer continuous speech is an edge case
- Silero VAD's built-in `prefix_padding_duration` (500ms default) is sufficient to capture speech onset
- The VAD filtering layer sits above the ASR provider abstraction, making it provider-agnostic by design

## Out of Scope

- Modifying any ASR provider's API configuration or server-side settings
- Implementing custom VAD models or training
- Real-time cost dashboard or billing integration
- Per-user or per-session configuration of VAD parameters
- Changing the overall voice agent architecture beyond the audio transmission path
- Provider-specific optimizations (all providers receive the same filtered audio stream)
