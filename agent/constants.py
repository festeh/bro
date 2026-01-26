# Text stream topics
TOPIC_TRANSCRIPTION = "lk.transcription"  # Synced with TTS
TOPIC_LLM_STREAM = "lk.llm_stream"        # Immediate LLM output
TOPIC_VAD_STATUS = "lk.vad_status"        # VAD gating notifications
TOPIC_TEXT_INPUT = "lk.text_input"        # Text messages from client

# Transcription attributes
ATTR_SEGMENT_ID = "lk.segment_id"
ATTR_TRANSCRIPTION_FINAL = "lk.transcription_final"

# Response metadata attributes
ATTR_RESPONSE_TYPE = "lk.response_type"
ATTR_MODEL = "lk.model"
ATTR_INTENT = "lk.intent"

# Task agent configuration
DIMAIST_CLI_PATH = "dimaist-cli"  # Default path, can be overridden via env
TASK_AGENT_TIMEOUT = 30.0  # CLI command timeout in seconds
MAX_CLI_RETRIES = 3  # LLM-assisted retry attempts on CLI failure
