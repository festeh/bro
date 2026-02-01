"""Centralized model configuration loaded from models.json."""

import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from langchain_openai import ChatOpenAI


@dataclass
class Provider:
    """Provider configuration."""

    name: str
    base_url: str | None
    api_key_env: str
    headers: dict[str, str] | None = None

    @property
    def api_key(self) -> str:
        """Get API key from environment."""
        return os.getenv(self.api_key_env, "")


@dataclass
class Model:
    """Model configuration."""

    name: str
    provider: str
    model_id: str
    extra_body: dict[str, Any] | None = None

    def get_provider(self) -> Provider:
        """Get the provider for this model."""
        return get_provider(self.provider)

    @property
    def base_url(self) -> str | None:
        """Get base URL from provider."""
        return self.get_provider().base_url

    @property
    def api_key(self) -> str:
        """Get API key from provider."""
        return self.get_provider().api_key

    @property
    def headers(self) -> dict[str, str] | None:
        """Get default headers from provider."""
        return self.get_provider().headers

    @property
    def display_name(self) -> str:
        """Display name with provider prefix."""
        return f"{self.provider}/{self.name}"


# Load config from models.json
_config_path = Path(__file__).parent.parent / "models.json"
with open(_config_path) as f:
    _config = json.load(f)

# Parse providers
_providers: dict[str, Provider] = {}
for name, data in _config["providers"].items():
    _providers[name] = Provider(
        name=name,
        base_url=data.get("base_url"),
        api_key_env=data["api_key_env"],
        headers=data.get("headers"),
    )

# Parse models
_llm_models: list[Model] = [
    Model(name=m["name"], provider=m["provider"], model_id=m["model_id"], extra_body=m.get("extra_body"))
    for m in _config["llm"]
]

_asr_models: list[Model] = [
    Model(name=m["name"], provider=m["provider"], model_id=m["model_id"]) for m in _config["asr"]
]

_tts_models: list[Model] = [
    Model(name=m["name"], provider=m["provider"], model_id=m["model_id"]) for m in _config["tts"]
]


def get_provider(name: str) -> Provider:
    """Get provider by name."""
    if name not in _providers:
        raise ValueError(f"Unknown provider: {name}")
    return _providers[name]


def get_llm_models() -> list[Model]:
    """Get all LLM models."""
    return _llm_models


def get_asr_models() -> list[Model]:
    """Get all ASR models."""
    return _asr_models


def get_tts_models() -> list[Model]:
    """Get all TTS models."""
    return _tts_models


def get_llm_by_index(index: int) -> Model:
    """Get LLM model by index, wrapping around."""
    return _llm_models[index % len(_llm_models)]


def get_default_llm() -> Model:
    """Get default LLM model (first in list)."""
    return _llm_models[0]


def get_llm_by_model_id(model_id: str) -> Model | None:
    """Find LLM model by model_id."""
    for model in _llm_models:
        if model.model_id == model_id:
            return model
    return None


def create_chat_llm(
    model_id: str,
    *,
    streaming: bool = True,
    callbacks: list[Any] | None = None,
) -> ChatOpenAI:
    """Create a ChatOpenAI client from model_id.

    Single source of truth for ChatOpenAI construction — handles
    provider headers, extra_body, and all provider-specific config.

    Raises:
        ValueError: If model_id is not found in models.json
    """
    model = get_llm_by_model_id(model_id)
    if not model:
        raise ValueError(f"Unknown model_id: {model_id!r}. Check models.json configuration.")
    kwargs: dict[str, Any] = {}
    if model.extra_body:
        kwargs["model_kwargs"] = {"extra_body": model.extra_body}
    if callbacks:
        kwargs["callbacks"] = callbacks
    return ChatOpenAI(
        base_url=model.base_url,  # pyright: ignore[reportArgumentType]
        api_key=model.api_key,  # pyright: ignore[reportArgumentType]
        model=model.model_id,  # pyright: ignore[reportArgumentType]
        streaming=streaming,
        default_headers=model.headers or {},
        **kwargs,
    )
