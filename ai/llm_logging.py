"""LLM request logging callback for LangChain."""

import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Any
from uuid import UUID

from langchain_core.callbacks import BaseCallbackHandler
from langchain_core.messages import BaseMessage

# Log file path
LLM_LOG_PATH = Path("/tmp/bro-logs/llm_requests.log")


def _setup_llm_logger() -> logging.Logger:
    """Setup dedicated file logger for LLM requests."""
    logger = logging.getLogger("bro.llm_requests")
    logger.setLevel(logging.DEBUG)
    logger.propagate = False  # Don't send to root logger

    # Only add handler if not already added
    if not logger.handlers:
        LLM_LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        handler = logging.FileHandler(LLM_LOG_PATH, encoding="utf-8")
        handler.setFormatter(logging.Formatter("%(message)s"))
        logger.addHandler(handler)

    return logger


_llm_logger = _setup_llm_logger()


def _serialize_messages(messages: list[BaseMessage]) -> list[dict[str, Any]]:
    """Convert LangChain messages to serializable dicts."""
    result = []
    for msg in messages:
        entry: dict[str, Any] = {
            "type": msg.type,
            "content": msg.content,
        }
        # Include additional kwargs if present (e.g., function_call, tool_calls)
        if hasattr(msg, "additional_kwargs") and msg.additional_kwargs:
            entry["additional_kwargs"] = msg.additional_kwargs
        result.append(entry)
    return result


class LLMRequestLogger(BaseCallbackHandler):
    """Callback handler that logs LLM requests to a dedicated file."""

    def __init__(self, context: str | None = None) -> None:
        """Initialize the logger.

        Args:
            context: Optional context string to identify the caller (e.g., "graph", "task_agent")
        """
        super().__init__()
        self.context = context

    def on_llm_start(
        self,
        serialized: dict[str, Any],
        prompts: list[str],
        *,
        run_id: UUID,
        parent_run_id: UUID | None = None,
        tags: list[str] | None = None,
        metadata: dict[str, Any] | None = None,
        **kwargs: Any,
    ) -> None:
        """Log when LLM starts processing (for non-chat models)."""
        log_entry = {
            "timestamp": datetime.now().isoformat(),
            "type": "llm_start",
            "context": self.context,
            "run_id": str(run_id),
            "model": serialized.get("kwargs", {}).get("model", "unknown"),
            "prompts": prompts,
        }
        _llm_logger.info(json.dumps(log_entry, ensure_ascii=False))

    def on_chat_model_start(
        self,
        serialized: dict[str, Any],
        messages: list[list[BaseMessage]],
        *,
        run_id: UUID,
        parent_run_id: UUID | None = None,
        tags: list[str] | None = None,
        metadata: dict[str, Any] | None = None,
        **kwargs: Any,
    ) -> None:
        """Log when chat model starts (the main entry point for ChatOpenAI)."""
        # Extract model info from serialized dict
        model_kwargs = serialized.get("kwargs", {})
        model = model_kwargs.get("model") or model_kwargs.get("model_name", "unknown")
        base_url = model_kwargs.get("base_url", "")

        # Serialize all message batches
        serialized_messages = [_serialize_messages(batch) for batch in messages]

        log_entry = {
            "timestamp": datetime.now().isoformat(),
            "type": "chat_model_start",
            "context": self.context,
            "run_id": str(run_id),
            "model": model,
            "base_url": base_url,
            "messages": serialized_messages,
        }

        # Include any bound functions/tools if present
        if "functions" in model_kwargs:
            log_entry["functions"] = model_kwargs["functions"]
        if "tools" in model_kwargs:
            log_entry["tools"] = model_kwargs["tools"]

        _llm_logger.info(json.dumps(log_entry, ensure_ascii=False, default=str))


def get_llm_callbacks(context: str | None = None) -> list[BaseCallbackHandler]:
    """Get callback handlers for LLM logging.

    Args:
        context: Optional context string (e.g., "graph.classify", "task_agent")

    Returns:
        List of callback handlers to pass to LLM
    """
    return [LLMRequestLogger(context=context)]
