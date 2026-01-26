# Spec: JSON Response Metadata

## Problem

The agent sends plain text chunks to the frontend. There's no metadata about the response (model used, intent detected, message type). The frontend displays only the text.

## Solution

Send JSON objects instead of plain text for LLM responses. Include metadata fields. Frontend parses and displays both text and metadata.

## Requirements

1. **Agent sends JSON response objects** with fields:
   - `type`: message type (e.g., "llm_response", "task_response", "error")
   - `text`: the response text chunk
   - `model`: LLM model ID used
   - `intent`: detected intent (if classified)

2. **Frontend parses JSON** from the LLM stream topic

3. **Frontend displays metadata** alongside the response text (model badge, intent indicator)

4. **Backward compatibility**: If plain text received (no JSON), treat as text-only

## Out of Scope

- Changing session notifications (already JSON)
- Changing transcription format (user speech)
- Adding new metadata fields beyond the core set
