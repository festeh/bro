"""Configuration for the AI server with multi-provider support."""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Settings loaded from environment variables."""

    # LLM Configuration
    llm_base_url: str = "https://api.groq.com/openai/v1"
    llm_api_key: str = ""
    llm_model: str = "qwen/qwen3-32b"

    # Provider-specific API keys
    groq_api_key: str = ""
    openrouter_api_key: str = ""
    gemini_api_key: str = ""
    chutes_api_key: str = ""
    elevenlabs_api_key: str = ""
    brave_api_key: str = ""

    # Server Configuration
    ws_host: str = "0.0.0.0"
    ws_port: int = 8000

    # Database Configuration
    db_path: str = "./chat.db"

    # Logging Configuration
    log_level: str = "INFO"
    json_logs: bool = False

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8", "extra": "ignore"}


settings = Settings()


def get_provider_config(provider: str) -> dict:
    """Get LLM config for a specific provider.

    Uses models_config as source of truth.
    """
    from ai.models_config import get_llm_models, get_provider

    provider_config = get_provider(provider)

    # Find first model for this provider
    models = get_llm_models()
    default_model = next((m for m in models if m.provider == provider), models[0])

    return {
        "base_url": provider_config.base_url,
        "api_key": provider_config.api_key,
        "model": default_model.model_id,
    }
