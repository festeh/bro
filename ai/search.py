"""Web search integration using Brave Search API."""

from typing import Any

from langchain_community.tools import BraveSearch

from ai.config import settings
from ai.logging_config import get_logger

log = get_logger(__name__)


async def search_web(query: str, max_results: int = 5) -> list[dict[str, Any]]:
    """Execute web search and return results.

    Args:
        query: The search query string
        max_results: Maximum number of results to return

    Returns:
        List of search results with title, link, and snippet
    """
    if not settings.brave_api_key:
        log.warning("brave_api_key_missing", query=query)
        return []

    try:
        search = BraveSearch.from_api_key(
            api_key=settings.brave_api_key,
            search_kwargs={"count": max_results},
        )
        results = await search.ainvoke(query)

        log.info(
            "search_completed",
            query=query,
            result_count=len(results) if isinstance(results, list) else 1,
        )

        # BraveSearch returns a string, parse it if needed
        if isinstance(results, str):
            # Return as single result if string
            return [{"snippet": results}]

        return results

    except Exception as e:
        log.error("search_failed", query=query, error=str(e))
        return []


def format_search_results(results: list[dict[str, Any]]) -> str:
    """Format search results into a string for LLM context.

    Args:
        results: List of search result dictionaries

    Returns:
        Formatted string of search results
    """
    if not results:
        return "No search results found."

    formatted = []
    for i, result in enumerate(results, 1):
        title = result.get("title", "")
        snippet = result.get("snippet", result.get("description", ""))
        link = result.get("link", result.get("url", ""))

        parts = [f"{i}."]
        if title:
            parts.append(f"**{title}**")
        if snippet:
            parts.append(snippet)
        if link:
            parts.append(f"Source: {link}")

        formatted.append(" ".join(parts))

    return "\n\n".join(formatted)
