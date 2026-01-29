"""LangGraph chat graph with intent classification and persistence."""

from collections.abc import AsyncIterator
from typing import Any, cast

from langchain_core.messages import BaseMessage, HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI
from langgraph.checkpoint.sqlite.aio import AsyncSqliteSaver
from langgraph.graph import START, MessagesState, StateGraph

from ai.config import settings
from ai.models_config import get_llm_by_model_id
from ai.logging_config import get_graph_logger
from ai.llm_logging import get_llm_callbacks
from ai.models import Intent, IntentClassification
from ai.search import format_search_results, search_web

log = get_graph_logger()

# System prompt for intent classification
CLASSIFICATION_SYSTEM_PROMPT = """You are an AI assistant that classifies user intents and responds appropriately.

For each user message, you must:
1. Classify the intent into one of four categories:
   - "direct_response": General conversation, greetings, questions you can answer from knowledge
   - "web_search": Questions about current events, real-time data, recent news, prices, weather
   - "end_dialog": Farewells, goodbyes, "thanks that's all", dismissals
   - "task_management": Creating, listing, completing, updating, or deleting tasks/todos

2. Provide a confidence score (0.0 to 1.0) for your classification

3. If intent is "web_search", extract a well-formed search query from the user's message

4. Generate an appropriate response:
   - For direct_response: Answer the question or continue the conversation
   - For web_search: Generate a placeholder (will be replaced with search results)
   - For end_dialog: Provide a friendly farewell message
   - For task_management: Generate a placeholder (will be handled by task agent)

Classification guidelines:
- Default to direct_response if unsure
- Use web_search only for genuinely time-sensitive or current information
- Common farewells: goodbye, bye, see you, thanks that's all, stop, end conversation
- Task management examples: "add task", "what's due today", "complete the milk task", "remind me to", "my tasks", "what do I need to do", "mark X as done\""""


def create_llm(model_id: str, context: str | None = None) -> ChatOpenAI:
    """Create the LLM client from model_id.

    Args:
        model_id: Model identifier from models.json (e.g., "qwen/qwen3-32b")
        context: Optional context for logging (e.g., "classify", "stream")

    Raises:
        ValueError: If model_id is not found in models.json
    """
    model = get_llm_by_model_id(model_id)
    if not model:
        raise ValueError(f"Unknown model_id: {model_id!r}. Check models.json configuration.")
    callbacks = get_llm_callbacks(context)
    log.debug("llm_created", provider=model.provider, model=model.model_id)
    return ChatOpenAI(
        base_url=model.base_url,  # pyright: ignore[reportArgumentType]
        api_key=model.api_key,  # pyright: ignore[reportArgumentType]
        model=model.model_id,  # pyright: ignore[reportArgumentType]
        streaming=True,
        callbacks=callbacks,
    )


async def classify_intent(
    messages: list[tuple[str, str] | BaseMessage], *, model_id: str
) -> IntentClassification:
    """Classify the user's intent from their message.

    Args:
        messages: The conversation messages including the latest user message
        model_id: Model identifier from models.json

    Returns:
        IntentClassification with intent, confidence, search_query, and response
    """
    llm = create_llm(model_id, context="graph.classify")

    # Use function calling for structured output (compatible with OpenAI-compatible APIs)
    classifier = llm.with_structured_output(
        IntentClassification,
        method="function_calling",
    )

    # Build messages with system prompt
    classification_messages = [
        SystemMessage(content=CLASSIFICATION_SYSTEM_PROMPT),
        *[
            HumanMessage(content=m[1]) if m[0] == "user" else m
            for m in messages
            if isinstance(m, tuple)
        ],
    ]

    # Handle non-tuple messages (e.g., from history)
    for m in messages:
        if not isinstance(m, tuple) and hasattr(m, "content"):
            if hasattr(m, "type") and m.type == "human":
                classification_messages.append(HumanMessage(content=m.content))

    raw_result = await classifier.ainvoke(classification_messages)
    result = cast(IntentClassification, raw_result)
    log.info(
        "intent_classified",
        intent=result.intent,
        confidence=result.confidence,
        response=result.response[:80] + "..." if len(result.response) > 80 else result.response,
    )
    return result


async def chat_node(state: MessagesState) -> MessagesState:
    """Process messages and generate a response.

    NOTE: Currently unused — stream_response bypasses the graph pipeline.
    Keeping for potential future use with LangGraph.
    """
    raise NotImplementedError("chat_node requires model_id; use stream_response instead")


def create_graph() -> StateGraph[MessagesState]:
    """Create the chat graph."""
    graph: StateGraph[MessagesState] = StateGraph(MessagesState)  # type: ignore[arg-type]
    graph.add_node("chat", chat_node)
    graph.add_edge(START, "chat")
    log.debug("graph_created")
    return graph


async def create_app_with_checkpointer():
    """Create the compiled graph with SQLite persistence."""
    graph = create_graph()
    # from_conn_string returns an async context manager
    checkpointer_cm = AsyncSqliteSaver.from_conn_string(settings.db_path)
    checkpointer = await checkpointer_cm.__aenter__()
    log.info("checkpointer_initialized", db_path=settings.db_path)
    return graph.compile(checkpointer=checkpointer), checkpointer_cm


async def stream_response(
    app: Any, thread_id: str, user_message: str, model_id: str
) -> AsyncIterator[str | dict[str, Any]]:
    """Stream the AI response with intent classification.

    Yields either:
    - str: Response text chunks
    - dict: Special events like {"type": "conversation_ended", ...}
    """
    log.debug(
        "stream_start",
        thread_id=thread_id,
        model_id=model_id,
        message_length=len(user_message),
    )

    # Get current history
    config = {"configurable": {"thread_id": thread_id}}
    state = await app.aget_state(config)

    # Build messages list
    messages = list(state.values.get("messages", [])) if state.values else []
    messages.append(("user", user_message))

    log.debug("history_loaded", thread_id=thread_id, history_length=len(messages) - 1)

    # Classify intent
    classification = await classify_intent(messages, model_id=model_id)

    # Log classification
    log.info(
        "intent_classified",
        thread_id=thread_id,
        intent=classification.intent,
        confidence=classification.confidence,
        input_summary=user_message[:100],
        search_query=classification.search_query,
    )

    # Route based on intent
    if classification.intent == Intent.END_DIALOG:
        # Yield farewell response
        yield classification.response

        # Save to state
        await app.aupdate_state(
            config,
            {
                "messages": [
                    ("user", user_message),
                    ("assistant", classification.response),
                ]
            },
        )

        # Yield conversation_ended event
        yield {
            "type": "conversation_ended",
            "message": classification.response,
        }

        log.debug("dialog_ended", thread_id=thread_id)
        return

    elif classification.intent == Intent.WEB_SEARCH:
        # Perform web search
        search_query = classification.search_query or user_message
        search_results = await search_web(search_query)
        formatted_results = format_search_results(search_results)

        log.debug(
            "search_performed",
            thread_id=thread_id,
            query=search_query,
            result_count=len(search_results),
        )

        # Generate response with search context
        search_context_messages = messages + [
            (
                "system",
                f"Here are the search results for '{search_query}':\n\n{formatted_results}\n\n"
                "Please synthesize these results into a helpful, conversational response. "
                "Include relevant information from the search results.",
            )
        ]

        llm = create_llm(model_id, context="graph.search")
        full_response = ""
        token_count = 0

        async for chunk in llm.astream(search_context_messages):
            if chunk.content and isinstance(chunk.content, str):
                full_response += chunk.content
                token_count += 1
                yield chunk.content

        # Save to state
        await app.aupdate_state(
            config,
            {"messages": [("user", user_message), ("assistant", full_response)]},
        )

        log.debug(
            "search_response_complete",
            thread_id=thread_id,
            tokens=token_count,
            response_length=len(full_response),
        )

    else:
        # Direct response - stream the classified response or generate fresh
        llm = create_llm(model_id, context="graph.direct")
        full_response = ""
        token_count = 0

        async for chunk in llm.astream(messages):
            if chunk.content and isinstance(chunk.content, str):
                full_response += chunk.content
                token_count += 1
                yield chunk.content

        # Save to state
        await app.aupdate_state(
            config,
            {"messages": [("user", user_message), ("assistant", full_response)]},
        )

        log.debug(
            "stream_complete",
            thread_id=thread_id,
            tokens=token_count,
            response_length=len(full_response),
        )


async def get_history(app: Any, thread_id: str) -> list[dict[str, Any]]:
    """Get conversation history for a thread."""
    config = {"configurable": {"thread_id": thread_id}}
    state = await app.aget_state(config)

    if not state.values:
        log.debug("history_empty", thread_id=thread_id)
        return []

    messages = []
    for msg in state.values.get("messages", []):
        messages.append(
            {
                "role": msg.type if hasattr(msg, "type") else "unknown",
                "content": msg.content,
            }
        )

    log.debug("history_retrieved", thread_id=thread_id, message_count=len(messages))
    return messages
