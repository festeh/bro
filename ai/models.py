"""Pydantic models for intent classification."""

from typing import Literal, Optional

from pydantic import BaseModel, Field


class IntentClassification(BaseModel):
    """Result of classifying user intent."""

    intent: Literal["direct_response", "web_search", "end_dialog", "task_management"] = Field(
        description="The classified intent: direct_response for general conversation/knowledge, "
        "web_search for queries requiring current information, end_dialog for farewells, "
        "task_management for creating/querying/completing tasks"
    )
    confidence: float = Field(
        ge=0.0,
        le=1.0,
        description="Confidence score for the classification (0.0 to 1.0)",
    )
    search_query: Optional[str] = Field(
        default=None,
        description="Search query to use when intent is web_search. "
        "Should be a well-formed search query extracted/reformulated from user message.",
    )
    response: str = Field(description="The response text to send to the user")
