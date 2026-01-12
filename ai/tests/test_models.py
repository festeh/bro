"""Tests for models.py - IntentClassification validation."""

import pytest
from pydantic import ValidationError

from ai.models import IntentClassification


class TestIntentClassification:
    """Tests for IntentClassification model."""

    def test_valid_direct_response(self):
        """Test valid direct_response intent."""
        result = IntentClassification(
            intent="direct_response",
            confidence=0.95,
            response="Hello! How can I help you?",
        )
        assert result.intent == "direct_response"
        assert result.confidence == 0.95
        assert result.search_query is None
        assert result.response == "Hello! How can I help you?"

    def test_valid_web_search(self):
        """Test valid web_search intent with search query."""
        result = IntentClassification(
            intent="web_search",
            confidence=0.85,
            search_query="current weather London",
            response="Let me search for that.",
        )
        assert result.intent == "web_search"
        assert result.confidence == 0.85
        assert result.search_query == "current weather London"

    def test_valid_end_dialog(self):
        """Test valid end_dialog intent."""
        result = IntentClassification(
            intent="end_dialog",
            confidence=0.99,
            response="Goodbye! Have a great day!",
        )
        assert result.intent == "end_dialog"
        assert result.confidence == 0.99

    def test_invalid_intent(self):
        """Test that invalid intent raises validation error."""
        with pytest.raises(ValidationError):
            IntentClassification(
                intent="invalid_intent",
                confidence=0.5,
                response="Test",
            )

    def test_confidence_bounds_low(self):
        """Test that confidence below 0 raises validation error."""
        with pytest.raises(ValidationError):
            IntentClassification(
                intent="direct_response",
                confidence=-0.1,
                response="Test",
            )

    def test_confidence_bounds_high(self):
        """Test that confidence above 1 raises validation error."""
        with pytest.raises(ValidationError):
            IntentClassification(
                intent="direct_response",
                confidence=1.5,
                response="Test",
            )

    def test_confidence_edge_zero(self):
        """Test that confidence of exactly 0 is valid."""
        result = IntentClassification(
            intent="direct_response",
            confidence=0.0,
            response="Test",
        )
        assert result.confidence == 0.0

    def test_confidence_edge_one(self):
        """Test that confidence of exactly 1 is valid."""
        result = IntentClassification(
            intent="direct_response",
            confidence=1.0,
            response="Test",
        )
        assert result.confidence == 1.0

    def test_missing_response(self):
        """Test that missing response raises validation error."""
        with pytest.raises(ValidationError):
            IntentClassification(
                intent="direct_response",
                confidence=0.5,
            )

    def test_search_query_optional(self):
        """Test that search_query is optional."""
        result = IntentClassification(
            intent="web_search",
            confidence=0.8,
            response="Searching...",
        )
        assert result.search_query is None
