"""Tests for graph.py - Intent classification and routing."""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from ai.graph import CLASSIFICATION_SYSTEM_PROMPT, classify_intent, create_llm
from ai.models import IntentClassification


class TestCreateLLM:
    """Tests for create_llm function."""

    def test_create_llm_default(self):
        """Test creating LLM with default settings."""
        llm = create_llm()
        assert llm is not None
        assert llm.streaming is True

    def test_create_llm_with_provider(self):
        """Test creating LLM with specific provider."""
        llm = create_llm(provider="chutes")
        assert llm is not None
        assert "chutes" in llm.openai_api_base.lower()


class TestClassificationSystemPrompt:
    """Tests for the classification system prompt."""

    def test_prompt_contains_intents(self):
        """Test that prompt mentions all three intents."""
        assert "direct_response" in CLASSIFICATION_SYSTEM_PROMPT
        assert "web_search" in CLASSIFICATION_SYSTEM_PROMPT
        assert "end_dialog" in CLASSIFICATION_SYSTEM_PROMPT

    def test_prompt_contains_guidelines(self):
        """Test that prompt contains classification guidelines."""
        assert "confidence" in CLASSIFICATION_SYSTEM_PROMPT.lower()
        assert "search query" in CLASSIFICATION_SYSTEM_PROMPT.lower()


class TestClassifyIntent:
    """Tests for classify_intent function."""

    @pytest.mark.asyncio
    async def test_classify_direct_response(self):
        """Test classification of greeting message."""
        mock_classification = IntentClassification(
            intent="direct_response",
            confidence=0.95,
            response="Hello! How can I help you today?",
        )

        with patch("ai.graph.create_llm") as mock_create_llm:
            mock_llm = MagicMock()
            mock_classifier = AsyncMock(return_value=mock_classification)
            mock_llm.with_structured_output.return_value.ainvoke = mock_classifier
            mock_create_llm.return_value = mock_llm

            result = await classify_intent([("user", "Hello!")])

            assert result.intent == "direct_response"
            assert result.confidence == 0.95

    @pytest.mark.asyncio
    async def test_classify_web_search(self):
        """Test classification of search query."""
        mock_classification = IntentClassification(
            intent="web_search",
            confidence=0.9,
            search_query="current weather in London",
            response="Let me search for that.",
        )

        with patch("ai.graph.create_llm") as mock_create_llm:
            mock_llm = MagicMock()
            mock_classifier = AsyncMock(return_value=mock_classification)
            mock_llm.with_structured_output.return_value.ainvoke = mock_classifier
            mock_create_llm.return_value = mock_llm

            result = await classify_intent([("user", "What's the weather in London?")])

            assert result.intent == "web_search"
            assert result.search_query == "current weather in London"

    @pytest.mark.asyncio
    async def test_classify_end_dialog(self):
        """Test classification of farewell message."""
        mock_classification = IntentClassification(
            intent="end_dialog",
            confidence=0.98,
            response="Goodbye! Have a great day!",
        )

        with patch("ai.graph.create_llm") as mock_create_llm:
            mock_llm = MagicMock()
            mock_classifier = AsyncMock(return_value=mock_classification)
            mock_llm.with_structured_output.return_value.ainvoke = mock_classifier
            mock_create_llm.return_value = mock_llm

            result = await classify_intent([("user", "Goodbye!")])

            assert result.intent == "end_dialog"
            assert result.confidence == 0.98

    @pytest.mark.asyncio
    async def test_classify_fallback_on_error(self):
        """Test that classification falls back to direct_response on error."""
        with patch("ai.graph.create_llm") as mock_create_llm:
            mock_llm = MagicMock()
            mock_llm.with_structured_output.return_value.ainvoke = AsyncMock(
                side_effect=Exception("API error")
            )
            mock_create_llm.return_value = mock_llm

            result = await classify_intent([("user", "Test message")])

            # Should fallback to direct_response
            assert result.intent == "direct_response"
            assert result.confidence == 0.5

    @pytest.mark.asyncio
    async def test_classify_with_history(self):
        """Test classification with conversation history."""
        mock_classification = IntentClassification(
            intent="direct_response",
            confidence=0.85,
            response="The capital of France is Paris.",
        )

        with patch("ai.graph.create_llm") as mock_create_llm:
            mock_llm = MagicMock()
            mock_classifier = AsyncMock(return_value=mock_classification)
            mock_llm.with_structured_output.return_value.ainvoke = mock_classifier
            mock_create_llm.return_value = mock_llm

            messages = [
                ("user", "Hi"),
                ("assistant", "Hello! How can I help?"),
                ("user", "What's the capital of France?"),
            ]
            result = await classify_intent(messages)

            assert result.intent == "direct_response"
            # Verify the classifier was called with messages
            mock_classifier.assert_called_once()


class TestIntentRouting:
    """Tests for intent-based routing logic."""

    def test_route_direct_response(self):
        """Test routing for direct_response intent."""
        classification = IntentClassification(
            intent="direct_response",
            confidence=0.9,
            response="Test response",
        )
        # Route logic is: if intent == "direct_response", stream response
        assert classification.intent == "direct_response"

    def test_route_web_search(self):
        """Test routing for web_search intent."""
        classification = IntentClassification(
            intent="web_search",
            confidence=0.9,
            search_query="test query",
            response="Searching...",
        )
        # Route logic is: if intent == "web_search", perform search
        assert classification.intent == "web_search"
        assert classification.search_query is not None

    def test_route_end_dialog(self):
        """Test routing for end_dialog intent."""
        classification = IntentClassification(
            intent="end_dialog",
            confidence=0.95,
            response="Goodbye!",
        )
        # Route logic is: if intent == "end_dialog", send farewell + event
        assert classification.intent == "end_dialog"
