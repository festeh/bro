"""Model list for the test stand - loaded from central models.json."""

from ai.models_config import Model, get_default_llm, get_llm_by_index, get_llm_models

# Re-export for backwards compatibility
MODELS = get_llm_models()


def get_model_by_index(index: int) -> Model:
    """Get model by index, wrapping around."""
    return get_llm_by_index(index)


def get_default_model() -> Model:
    """Get the default model (first in list)."""
    return get_default_llm()
