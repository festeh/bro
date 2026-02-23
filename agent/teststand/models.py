"""Model configuration for the test stand."""

from dataclasses import dataclass


@dataclass
class Model:
    """Simple model reference for the test stand UI."""

    model_id: str
    display_name: str


# Static list of commonly used models for cycling in the TUI.
MODELS = [
    Model(model_id="default", display_name="default"),
    Model(model_id="qwen/qwen3-32b", display_name="qwen3-32b"),
    Model(model_id="moonshotai/kimi-k2-instruct", display_name="kimi-k2-instruct"),
]


def get_model_by_index(index: int) -> Model:
    return MODELS[index % len(MODELS)]


def get_default_model() -> Model:
    return MODELS[0]
