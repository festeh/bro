# Tasks: ASR Cost Optimization

**Input**: Design documents from `/specs/002-deepgram-cost-optimization/`
**Prerequisites**: plan.md, spec.md, data-model.md, contracts/, research.md, quickstart.md

**Tests**: Not explicitly requested - test tasks omitted.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Backend**: `agent/` (Python voice agent)
- **Frontend**: `desktop/lib/` (Flutter desktop app)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Add constants and type definitions needed by all user stories

- [ ] T001 [P] Add TOPIC_VAD_STATUS constant in agent/constants.py
- [ ] T002 [P] Add vadStatus topic constant in desktop/lib/constants/livekit_constants.dart
- [ ] T003 [P] Add VADGatingConfig dataclass in agent/voice_agent.py (config fields from data-model.md)
- [ ] T004 [P] Add VADGatingState dataclass in agent/voice_agent.py (turn_id, warning_sent, asr_provider)
- [ ] T005 [P] Add VADGatingMetrics dataclass in agent/voice_agent.py (all metrics fields from data-model.md)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core notification infrastructure that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T006 Implement _send_vad_notification() helper method in agent/voice_agent.py using stream_text() pattern
- [ ] T007 Register VAD notification handler in desktop/lib/services/livekit_service.dart for lk.vad_status topic
- [ ] T008 Add VAD notification event types to frontend (turn_warning, turn_terminated, asr_connection_failed)

**Checkpoint**: Notification infrastructure ready - user story implementation can now begin

---

## Phase 3: User Story 1 - VAD-Gated Audio Transmission (Priority: P1) 🎯 MVP

**Goal**: Filter silence using VAD before sending audio to ASR providers, reducing billable audio by ~40%

**Independent Test**: Conduct voice session with natural pauses, verify only speech segments transmitted, transcription quality unchanged

### Implementation for User Story 1

- [ ] T009 [US1] Implement on_start_of_speech hook in agent/voice_agent.py - generate turn_id, reset warning_sent
- [ ] T010 [US1] Implement on_end_of_speech hook in agent/voice_agent.py - reset state, increment turns_completed
- [ ] T011 [US1] Add metrics accumulation in hooks - track total_audio_duration, transmitted_duration in agent/voice_agent.py
- [ ] T012 [US1] Configure Silero VAD min_silence_duration=0.3 in agent/voice_agent.py prewarm()
- [ ] T013 [US1] Verify VAD prefix_padding_duration=0.5 is set (pre-roll buffer) in agent/voice_agent.py

**Checkpoint**: VAD gating functional - silence is filtered, speech is transmitted, metrics accumulating

---

## Phase 4: User Story 2 - Turn Duration Limit Enforcement (Priority: P2)

**Goal**: Terminate turns exceeding 60 seconds with 5-second warning, preventing runaway costs

**Independent Test**: Speak continuously for 60+ seconds, verify warning at 55s, termination at 60s, frontend notified

### Implementation for User Story 2

- [ ] T014 [US2] Implement on_vad_inference_done hook in agent/voice_agent.py - check elapsed time against thresholds
- [ ] T015 [US2] Add 55-second warning logic in on_vad_inference_done - send turn_warning notification, set warning_sent=True
- [ ] T016 [US2] Add 60-second termination logic in on_vad_inference_done - send turn_terminated notification, increment turns_terminated
- [ ] T017 [US2] Implement 2-second grace period at turn boundary in agent/voice_agent.py
- [ ] T018 [US2] Handle turn_warning notification in desktop/lib/services/livekit_service.dart - emit event for UI
- [ ] T019 [US2] Handle turn_terminated notification in desktop/lib/services/livekit_service.dart - emit event for UI

**Checkpoint**: Turn limits enforced - warnings sent at 55s, termination at 60s, frontend receives notifications

---

## Phase 5: User Story 3 - Cost Monitoring Visibility (Priority: P3)

**Goal**: Log metrics showing filtered vs transmitted audio per session for cost savings visibility

**Independent Test**: Complete voice sessions, review logs for total/transmitted/filtered durations and filtering ratio

### Implementation for User Story 3

- [ ] T020 [US3] Add session_start_time tracking on session start in agent/voice_agent.py
- [ ] T021 [US3] Log VADGatingMetrics as JSON on session end in agent/voice_agent.py
- [ ] T022 [US3] Include filtering_ratio calculation in logged metrics (filtered/total)
- [ ] T023 [US3] Include asr_provider in all logged metrics for per-provider analysis

**Checkpoint**: Metrics visibility complete - session end logs show all cost-related metrics

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Edge cases, connection failure handling, and validation

- [ ] T024 [P] Implement ASR connection failure buffering (5s max) in agent/voice_agent.py
- [ ] T025 [P] Send asr_connection_failed notification on buffer discard in agent/voice_agent.py
- [ ] T026 [P] Handle asr_connection_failed notification in desktop/lib/services/livekit_service.dart
- [ ] T027 Add type hints and run mypy --strict on agent/voice_agent.py changes
- [ ] T028 Validate against quickstart.md scenarios in specs/002-deepgram-cost-optimization/quickstart.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-5)**: All depend on Foundational phase completion
  - US1 → US2 → US3 (recommended order, but can parallelize)
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational - Uses hooks from US1 but independently testable
- **User Story 3 (P3)**: Can start after Foundational - Uses metrics from US1 but independently testable

### Within Each User Story

- Hook implementations before UI handlers
- Backend before frontend
- Core logic before edge cases

### Parallel Opportunities

- All Setup tasks (T001-T005) marked [P] can run in parallel
- T001+T003+T004+T005 (backend) can run parallel with T002 (frontend)
- T024+T025 (backend) can run parallel with T026 (frontend)

---

## Parallel Example: Setup Phase

```bash
# Launch all setup tasks together:
Task: "Add TOPIC_VAD_STATUS constant in agent/constants.py"
Task: "Add vadStatus topic constant in desktop/lib/constants/livekit_constants.dart"
Task: "Add VADGatingConfig dataclass in agent/voice_agent.py"
Task: "Add VADGatingState dataclass in agent/voice_agent.py"
Task: "Add VADGatingMetrics dataclass in agent/voice_agent.py"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T005)
2. Complete Phase 2: Foundational (T006-T008)
3. Complete Phase 3: User Story 1 (T009-T013)
4. **STOP and VALIDATE**: Test VAD gating independently
5. Deploy if ready - already achieving ~40% cost reduction

### Incremental Delivery

1. Setup + Foundational → Infrastructure ready
2. Add User Story 1 → VAD filtering works → Deploy (MVP!)
3. Add User Story 2 → Turn limits enforced → Deploy
4. Add User Story 3 → Metrics visible → Deploy
5. Polish → Connection failure handling → Final deploy

### Effort Estimate

| Phase | Tasks | Complexity |
|-------|-------|------------|
| Setup | 5 | Low |
| Foundational | 3 | Medium |
| US1 (VAD Gating) | 5 | Medium |
| US2 (Turn Limits) | 6 | Medium |
| US3 (Metrics) | 4 | Low |
| Polish | 5 | Medium |
| **Total** | **28** | - |

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- All hook implementations extend existing RecognitionHooks pattern
- No new modules - all changes in existing files (DRY approach)
- Verify Silero VAD config before implementing gating logic
- Commit after each task or logical group
