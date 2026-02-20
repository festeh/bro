import json
import logging
from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any

from livekit.agents import JobContext
from livekit.plugins import deepgram, elevenlabs, openai

from ai.models_config import get_default_llm, get_llm_by_model_id

# Session inactivity timeout
SESSION_TIMEOUT = 60.0  # seconds without completed turn
SESSION_WARNING_THRESHOLD = 55.0  # seconds


class NotificationType(StrEnum):
    """Session notification types."""

    SESSION_WARNING = "session_warning"
    SESSION_TIMEOUT = "session_timeout"
    SESSION_READY = "session_ready"


logger = logging.getLogger("voice-agent")


@dataclass
class AgentSettings:
    """Configuration for agent behavior."""

    stt_provider: str = "deepgram"
    llm_model: str = field(default_factory=lambda: get_default_llm().model_id)
    tts_enabled: bool = True
    agent_mode: str = "chat"
    excluded_agents: list[str] = field(default_factory=list)

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "AgentSettings":
        return cls(
            stt_provider=d.get("stt_provider", "deepgram"),
            llm_model=d.get("llm_model", get_default_llm().model_id),
            tts_enabled=d.get("tts_enabled", True),
            agent_mode=d.get("agent_mode", "chat"),
            excluded_agents=d.get("excluded_agents", []),
        )


def create_stt(provider: str):
    """Create STT instance based on provider name."""
    if provider == "elevenlabs":
        return elevenlabs.STT()
    return deepgram.STT(model="nova-3")


def create_llm(model_id: str) -> openai.LLM | None:
    """Create LLM instance from model_id. Returns None if model not found."""
    model = get_llm_by_model_id(model_id)
    if not model:
        logger.error(f"Unknown model: {model_id}. Check models.json configuration.")
        return None

    return openai.LLM(
        model=model.model_id,
        base_url=model.base_url,  # pyright: ignore[reportArgumentType]
        api_key=model.api_key,
        extra_headers=model.headers or {},  # pyright: ignore[reportArgumentType]
        extra_body=model.extra_body or {},  # pyright: ignore[reportArgumentType]
    )


def get_settings_from_metadata(ctx: JobContext) -> AgentSettings:
    """Extract settings from participant or room metadata."""
    merged: dict[str, Any] = {}

    for participant in ctx.room.remote_participants.values():
        if participant.metadata:
            try:
                merged.update(json.loads(participant.metadata))
                logger.info(f"Settings from participant {participant.identity}: {merged}")
                break
            except json.JSONDecodeError:
                pass

    if ctx.room.metadata:
        try:
            merged.update(json.loads(ctx.room.metadata))
            logger.info(f"Settings from room metadata: {merged}")
        except json.JSONDecodeError:
            pass

    return AgentSettings.from_dict(merged)
