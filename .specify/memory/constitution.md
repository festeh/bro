<!--
Sync Impact Report
==================
Version change: N/A (initial) -> 1.0.0
Modified principles: N/A (initial creation)
Added sections: Core Principles (5), Technology Stack, Development Workflow, Governance
Removed sections: N/A
Templates requiring updates:
  - .specify/templates/plan-template.md: No updates needed (Constitution Check section is generic)
  - .specify/templates/spec-template.md: No updates needed (requirements are project-agnostic)
  - .specify/templates/tasks-template.md: No updates needed (task format is generic)
Follow-up TODOs: None
-->

# Bro Constitution

## Core Principles

### I. Modular Services

The system MUST be composed of loosely coupled, independently deployable services.

- Each platform app (phone, wear, desktop) MUST be a standalone Flutter project
- Backend services (LiveKit agent, AI server) MUST communicate via well-defined APIs
- No service MAY directly access another service's internal state or database
- Service boundaries MUST be clear: audio capture, transcription, LLM processing, TTS are separate concerns
- Each service MUST be runnable and testable in isolation

**Rationale**: Enables independent development, deployment, and scaling of each component. A bug in the AI server should not require rebuilding the Flutter apps.

### II. Type Safety

All code MUST use strong, explicit typing to catch errors at compile/lint time.

- Dart: Enable `strict-casts`, `strict-raw-types`, and `strict-inference` in analysis_options.yaml
- Python: All functions MUST have type hints; use `mypy --strict` or equivalent for validation
- API contracts MUST define explicit types for all request/response fields
- Avoid `dynamic`, `Any`, or `Object` types unless absolutely necessary (and document why)
- Generic types MUST specify their type parameters

**Rationale**: Type errors caught during development are orders of magnitude cheaper than runtime bugs in production.

### III. DRY with Pragmatism

Avoid duplication, but do not over-abstract prematurely.

- Duplicate code MUST be extracted only after 3+ occurrences
- Abstractions MUST solve a current problem, not a hypothetical future one
- Shared code between platforms goes in `shared/` or `packages/` only when proven necessary
- Copy-paste is acceptable for 2 similar implementations; refactor on the third
- Each abstraction MUST have at least 2 concrete use cases at time of creation

**Rationale**: Premature abstraction creates complexity without value. Let patterns emerge from real usage before generalizing.

### IV. Structured Logging

All services MUST emit structured, queryable logs.

- Logs MUST be JSON-formatted in production environments
- Every log entry MUST include: timestamp, level, service name, and message
- Error logs MUST include: error type, stack trace, and relevant context (user ID, request ID, etc.)
- Log levels: DEBUG (dev only), INFO (operations), WARN (recoverable issues), ERROR (failures)
- Sensitive data (API keys, tokens, PII) MUST NOT appear in logs

**Rationale**: Structured logs enable efficient debugging, monitoring, and alerting across distributed services.

### V. Break Things First

Move fast; backwards compatibility is not a constraint.

- Refactoring and breaking changes are always permitted
- No deprecated code: remove old implementations immediately when replaced
- No backwards-compatibility shims, migration layers, or version negotiation
- APIs MAY change without notice; clients MUST adapt
- If a better approach exists, implement it directly without preserving the old way

**Rationale**: This is a fast-moving project. Maintaining backwards compatibility slows iteration and accumulates technical debt. All clients are controlled, so breaking changes have no external impact.

## Technology Stack

**Flutter Apps** (phone, wear, desktop):
- Dart 3.x with null safety
- State management: Provider or Riverpod (consistent within each app)
- Platform channels for native audio/Bluetooth

**Backend Services**:
- Python 3.12+ with type hints
- LiveKit for real-time audio/video infrastructure
- FastAPI for HTTP endpoints
- uv for dependency management

**Infrastructure**:
- Redis for LiveKit coordination
- Local file storage for recordings
- pm2 for process management (development)

## Development Workflow

**Branching**: Work directly on `master` for small changes; feature branches for larger work.

**Code Style**:
- Dart: `dart format` with default settings
- Python: `ruff` for linting and formatting

**Commits**:
- Small, atomic commits preferred
- Descriptive messages explaining "why" not just "what"
- No merge commits; rebase to keep history linear

**Dependencies**:
- Justify each new dependency
- Prefer well-maintained libraries with strong typing support
- Pin versions in lock files

## Governance

This constitution establishes the non-negotiable principles for the Bro project. All code changes, architectural decisions, and tooling choices MUST comply with these principles.

**Amendments**:
- Any principle MAY be modified by updating this document
- Changes MUST include rationale for the amendment
- Version number MUST be incremented according to semantic versioning:
  - MAJOR: Removing or fundamentally redefining a principle
  - MINOR: Adding a new principle or expanding existing guidance
  - PATCH: Clarifications, typos, wording improvements

**Compliance**:
- Code review SHOULD verify adherence to these principles
- When in doubt, the constitution takes precedence over convention

**Version**: 1.0.0 | **Ratified**: 2026-01-09 | **Last Amended**: 2026-01-09
