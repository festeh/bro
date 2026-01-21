"""Merged model list from all providers for the test stand."""

from dataclasses import dataclass

from ai.config import settings


@dataclass
class Model:
    """A model configuration."""

    name: str  # Display name
    provider: str  # Provider key (groq, chutes, etc.)
    model_id: str  # Model ID to pass to API
    base_url: str
    api_key: str

    @property
    def display_name(self) -> str:
        """Short display name for UI."""
        return f"{self.provider}/{self.name}"


# All available models merged into one list
MODELS: list[Model] = [
    # Groq
    Model(
        name="llama-3.3-70b",
        provider="groq",
        model_id="llama-3.3-70b-versatile",
        base_url="https://api.groq.com/openai/v1",
        api_key=settings.groq_api_key,
    ),
    Model(
        name="qwen3-32b",
        provider="groq",
        model_id="qwen/qwen3-32b",
        base_url="https://api.groq.com/openai/v1",
        api_key=settings.groq_api_key,
    ),
    # Chutes
    Model(
        name="deepseek-v3",
        provider="chutes",
        model_id="deepseek-ai/DeepSeek-V3-0324",
        base_url="https://llm.chutes.ai/v1",
        api_key=settings.chutes_api_key,
    ),
    Model(
        name="deepseek-v3.1",
        provider="chutes",
        model_id="deepseek-ai/DeepSeek-V3.1-Terminus-TEE",
        base_url="https://llm.chutes.ai/v1",
        api_key=settings.chutes_api_key,
    ),
    Model(
        name="kimi-k2",
        provider="chutes",
        model_id="moonshotai/Kimi-K2-Thinking-TEE",
        base_url="https://llm.chutes.ai/v1",
        api_key=settings.chutes_api_key,
    ),
    Model(
        name="glm-4.7",
        provider="chutes",
        model_id="zai-org/GLM-4.7-TEE",
        base_url="https://llm.chutes.ai/v1",
        api_key=settings.chutes_api_key,
    ),
    # OpenRouter
    Model(
        name="llama-3.3-70b",
        provider="openrouter",
        model_id="meta-llama/llama-3.3-70b-instruct",
        base_url="https://openrouter.ai/api/v1",
        api_key=settings.openrouter_api_key,
    ),
    # Gemini
    Model(
        name="gemini-2.0-flash",
        provider="gemini",
        model_id="gemini-2.0-flash",
        base_url="https://generativelanguage.googleapis.com/v1beta/openai",
        api_key=settings.gemini_api_key,
    ),
]


def get_model_by_index(index: int) -> Model:
    """Get model by index, wrapping around."""
    return MODELS[index % len(MODELS)]


def get_default_model() -> Model:
    """Get the default model (first in list)."""
    return MODELS[0]
