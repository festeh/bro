"""Integration tests that call the real LLM.

These tests require valid API keys and make actual API calls.
Run with: uv run --group dev pytest tests/test_integration.py -v

To run these tests, ensure CHUTES_API_KEY is set in .env with a valid key.
"""

import pytest

from config import settings
from graph import classify_intent
from models import IntentClassification


async def check_api_works() -> bool:
    """Check if the Chutes API is accessible with current key."""
    if not settings.chutes_api_key:
        return False
    try:
        result = await classify_intent([("user", "test")], provider="chutes")
        # If we get a real response (not the fallback), API works
        return result.confidence != 0.5 or "trouble processing" not in result.response
    except Exception:
        return False


# Will be set by the first test to avoid repeated checks
_api_works = None


async def skip_if_api_broken():
    """Skip test if API is not working."""
    global _api_works
    if _api_works is None:
        _api_works = await check_api_works()
    if not _api_works:
        pytest.skip("Chutes API not accessible (invalid key or network issue)")


class TestRealClassification:
    """Integration tests using real LLM calls via Chutes.

    These tests verify actual classification behavior with real LLM responses.
    They require a valid CHUTES_API_KEY in .env.
    """

    @pytest.mark.asyncio
    async def test_classify_greeting(self):
        """Test that greetings are classified as direct_response."""
        await skip_if_api_broken()

        result = await classify_intent([("user", "Hello!")], provider="chutes")

        assert isinstance(result, IntentClassification)
        assert result.intent == "direct_response"
        assert result.confidence > 0.5
        assert len(result.response) > 0

    @pytest.mark.asyncio
    async def test_classify_general_knowledge(self):
        """Test that general knowledge questions are direct_response."""
        await skip_if_api_broken()

        result = await classify_intent(
            [("user", "What is the capital of France?")], provider="chutes"
        )

        assert result.intent == "direct_response"
        assert result.confidence > 0.5

    @pytest.mark.asyncio
    async def test_classify_current_events(self):
        """Test that current events questions trigger web_search."""
        await skip_if_api_broken()

        result = await classify_intent(
            [("user", "What happened in the news today?")], provider="chutes"
        )

        assert result.intent == "web_search"
        assert result.search_query is not None
        assert len(result.search_query) > 0

    @pytest.mark.asyncio
    async def test_classify_weather(self):
        """Test that weather questions trigger web_search."""
        await skip_if_api_broken()

        result = await classify_intent(
            [("user", "What's the weather in London right now?")], provider="chutes"
        )

        assert result.intent == "web_search"
        assert result.search_query is not None

    @pytest.mark.asyncio
    async def test_classify_goodbye(self):
        """Test that farewells are classified as end_dialog."""
        await skip_if_api_broken()

        result = await classify_intent([("user", "Goodbye!")], provider="chutes")

        assert result.intent == "end_dialog"
        assert result.confidence > 0.5
        assert len(result.response) > 0

    @pytest.mark.asyncio
    async def test_classify_thanks_done(self):
        """Test that 'thanks, that's all' is end_dialog."""
        await skip_if_api_broken()

        result = await classify_intent(
            [("user", "Thanks, that's all I needed!")], provider="chutes"
        )

        assert result.intent == "end_dialog"

    @pytest.mark.asyncio
    async def test_classify_with_context(self):
        """Test classification considers conversation context."""
        await skip_if_api_broken()

        messages = [
            ("user", "Hi"),
            ("assistant", "Hello! How can I help?"),
            ("user", "Tell me more about that"),
        ]
        result = await classify_intent(messages, provider="chutes")

        # Should be direct_response since it's a follow-up
        assert result.intent == "direct_response"

    @pytest.mark.asyncio
    async def test_classify_stock_price(self):
        """Test that stock price questions trigger web_search."""
        await skip_if_api_broken()

        result = await classify_intent(
            [("user", "What's the current price of Tesla stock?")], provider="chutes"
        )

        assert result.intent == "web_search"
        assert result.search_query is not None
