"""Configuration for the AI server with multi-provider support."""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Settings loaded from environment variables."""

    # LLM Configuration
    llm_base_url: str = "https://api.groq.com/openai/v1"
    llm_api_key: str = ""
    llm_model: str = "llama-3.3-70b-versatile"

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
    """Get LLM config for a specific provider."""
    presets = {
        "groq": {
            "base_url": "https://api.groq.com/openai/v1",
            "api_key": settings.groq_api_key,
            "model": "llama-3.3-70b-versatile",
        },
        "chutes": {
            "base_url": "https://llm.chutes.ai/v1",
            "api_key": settings.chutes_api_key,
            "model": "deepseek-ai/DeepSeek-V3-0324",
        },
        "openrouter": {
            "base_url": "https://openrouter.ai/api/v1",
            "api_key": settings.openrouter_api_key,
            "model": "meta-llama/llama-3.3-70b-instruct",
        },
        "gemini": {
            "base_url": "https://generativelanguage.googleapis.com/v1beta/openai",
            "api_key": settings.gemini_api_key,
            "model": "gemini-2.0-flash",
        },
    }
    return presets.get(provider, presets["groq"])
