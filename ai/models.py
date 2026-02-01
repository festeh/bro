"""Pydantic models for intent classification."""

from enum import StrEnum

from pydantic import BaseModel, Field


class Intent(StrEnum):
    """User intent classification."""

    DIRECT_RESPONSE = "direct_response"
    WEB_SEARCH = "web_search"
    END_DIALOG = "end_dialog"
    TASK_MANAGEMENT = "task_management"
    NOTES = "notes"


class IntentClassification(BaseModel):
    """Result of classifying user intent."""

    intent: Intent = Field(
        description="The classified intent: direct_response for general conversation/knowledge, "
        "web_search for queries requiring current information, end_dialog for farewells, "
        "task_management for creating/querying/completing tasks, "
        "notes for creating/searching/reading/organizing notes and files in the knowledge base"
    )
    confidence: float = Field(
        ge=0.0,
        le=1.0,
        description="Confidence score for the classification (0.0 to 1.0)",
    )
    search_query: str | None = Field(
        default=None,
        description="Search query to use when intent is web_search. "
        "Should be a well-formed search query extracted/reformulated from user message.",
    )
    response: str = Field(description="The response text to send to the user")
