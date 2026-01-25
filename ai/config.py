"""Configuration for the AI server with multi-provider support."""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Settings loaded from environment variables.

    Note: LLM/provider configs are in models_config.py (single source of truth).
    """

    # API keys for web search
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
