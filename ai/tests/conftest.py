"""Pytest configuration and fixtures."""

import sys
from pathlib import Path

import pytest

# Add the ai directory to the path so we can import modules
ai_dir = Path(__file__).parent.parent
sys.path.insert(0, str(ai_dir))


@pytest.fixture
def sample_search_results():
    """Sample search results for testing."""
    return [
        {
            "title": "Weather in London - Current Conditions",
            "snippet": "Current weather in London: 15°C, partly cloudy.",
            "link": "https://weather.example.com/london",
        },
        {
            "title": "London Weather Forecast",
            "snippet": "7-day forecast for London, UK.",
            "link": "https://forecast.example.com/london",
        },
    ]


@pytest.fixture
def sample_classification_direct():
    """Sample direct_response classification."""
    from models import IntentClassification

    return IntentClassification(
        intent="direct_response",
        confidence=0.95,
        response="Hello! How can I help you today?",
    )


@pytest.fixture
def sample_classification_search():
    """Sample web_search classification."""
    from models import IntentClassification

    return IntentClassification(
        intent="web_search",
        confidence=0.9,
        search_query="weather in London",
        response="Let me search for the current weather in London.",
    )


@pytest.fixture
def sample_classification_end():
    """Sample end_dialog classification."""
    from models import IntentClassification

    return IntentClassification(
        intent="end_dialog",
        confidence=0.98,
        response="Goodbye! Have a great day!",
    )
