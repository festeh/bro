"""Tests for search.py - Web search integration."""

import pytest

from search import format_search_results


class TestFormatSearchResults:
    """Tests for format_search_results function."""

    def test_empty_results(self):
        """Test formatting empty results."""
        result = format_search_results([])
        assert result == "No search results found."

    def test_single_result_full(self):
        """Test formatting a single result with all fields."""
        results = [
            {
                "title": "Test Article",
                "snippet": "This is a test snippet.",
                "link": "https://example.com/article",
            }
        ]
        formatted = format_search_results(results)
        assert "1." in formatted
        assert "**Test Article**" in formatted
        assert "This is a test snippet." in formatted
        assert "Source: https://example.com/article" in formatted

    def test_multiple_results(self):
        """Test formatting multiple results."""
        results = [
            {"title": "First", "snippet": "First snippet", "link": "https://a.com"},
            {"title": "Second", "snippet": "Second snippet", "link": "https://b.com"},
            {"title": "Third", "snippet": "Third snippet", "link": "https://c.com"},
        ]
        formatted = format_search_results(results)
        assert "1." in formatted
        assert "2." in formatted
        assert "3." in formatted
        assert "**First**" in formatted
        assert "**Second**" in formatted
        assert "**Third**" in formatted

    def test_result_with_description_fallback(self):
        """Test that 'description' field is used if 'snippet' is missing."""
        results = [
            {
                "title": "Test",
                "description": "Description text",
                "link": "https://example.com",
            }
        ]
        formatted = format_search_results(results)
        assert "Description text" in formatted

    def test_result_with_url_fallback(self):
        """Test that 'url' field is used if 'link' is missing."""
        results = [
            {
                "title": "Test",
                "snippet": "Snippet",
                "url": "https://example.com",
            }
        ]
        formatted = format_search_results(results)
        assert "Source: https://example.com" in formatted

    def test_result_minimal(self):
        """Test formatting result with only snippet."""
        results = [{"snippet": "Just a snippet"}]
        formatted = format_search_results(results)
        assert "1." in formatted
        assert "Just a snippet" in formatted

    def test_result_no_link(self):
        """Test formatting result without link/url."""
        results = [{"title": "Title", "snippet": "Snippet"}]
        formatted = format_search_results(results)
        assert "Source:" not in formatted


class TestSearchWeb:
    """Tests for search_web function (requires mocking)."""

    @pytest.mark.asyncio
    async def test_search_without_api_key(self):
        """Test that search returns empty list when API key is missing."""
        # This test verifies graceful handling when BRAVE_API_KEY is not set
        from search import search_web

        # API key is empty by default in tests
        results = await search_web("test query")
        assert results == []
