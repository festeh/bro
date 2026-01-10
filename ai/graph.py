"""LangGraph chat graph with intent classification and persistence."""

from typing import AsyncIterator, Optional

from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI
from langgraph.checkpoint.sqlite.aio import AsyncSqliteSaver
from langgraph.graph import START, MessagesState, StateGraph

from config import get_provider_config, settings
from logging_config import get_graph_logger
from models import IntentClassification
from search import format_search_results, search_web

log = get_graph_logger()

# System prompt for intent classification
CLASSIFICATION_SYSTEM_PROMPT = """You are an AI assistant that classifies user intents and responds appropriately.

For each user message, you must:
1. Classify the intent into one of three categories:
   - "direct_response": General conversation, greetings, questions you can answer from knowledge
   - "web_search": Questions about current events, real-time data, recent news, prices, weather
   - "end_dialog": Farewells, goodbyes, "thanks that's all", dismissals

2. Provide a confidence score (0.0 to 1.0) for your classification

3. If intent is "web_search", extract a well-formed search query from the user's message

4. Generate an appropriate response:
   - For direct_response: Answer the question or continue the conversation
   - For web_search: Generate a placeholder (will be replaced with search results)
   - For end_dialog: Provide a friendly farewell message

Classification guidelines:
- Default to direct_response if unsure
- Use web_search only for genuinely time-sensitive or current information
- Common farewells: goodbye, bye, see you, thanks that's all, stop, end conversation"""


def create_llm(provider: Optional[str] = None) -> ChatOpenAI:
    """Create the LLM client with configured provider."""
    if provider:
        config = get_provider_config(provider)
        log.debug("llm_created", provider=provider, model=config["model"])
        return ChatOpenAI(
            base_url=config["base_url"],
            api_key=config["api_key"],
            model=config["model"],
            streaming=True,
        )
    log.debug("llm_created", provider="default", model=settings.llm_model)
    return ChatOpenAI(
        base_url=settings.llm_base_url,
        api_key=settings.llm_api_key,
        model=settings.llm_model,
        streaming=True,
    )


async def classify_intent(
    messages: list, provider: Optional[str] = None
) -> IntentClassification:
    """Classify the user's intent from their message.

    Args:
        messages: The conversation messages including the latest user message
        provider: Optional LLM provider to use

    Returns:
        IntentClassification with intent, confidence, search_query, and response
    """
    llm = create_llm(provider)

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

    try:
        result = await classifier.ainvoke(classification_messages)
        return result
    except Exception as e:
        log.error("classification_failed", error=str(e))
        # Fallback to direct_response on error
        return IntentClassification(
            intent="direct_response",
            confidence=0.5,
            search_query=None,
            response="I'm having trouble processing your request. Could you try rephrasing?",
        )


async def chat_node(state: MessagesState) -> MessagesState:
    """Process messages and generate a response."""
    llm = create_llm()
    response = await llm.ainvoke(state["messages"])
    return {"messages": [response]}


def create_graph() -> StateGraph:
    """Create the chat graph."""
    graph = StateGraph(MessagesState)
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
    app, thread_id: str, user_message: str, provider: Optional[str] = None
) -> AsyncIterator[str | dict]:
    """Stream the AI response with intent classification.

    Yields either:
    - str: Response text chunks
    - dict: Special events like {"type": "conversation_ended", ...}
    """
    log.debug(
        "stream_start",
        thread_id=thread_id,
        provider=provider or "default",
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
    classification = await classify_intent(messages, provider)

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
    if classification.intent == "end_dialog":
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

    elif classification.intent == "web_search":
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

        llm = create_llm(provider)
        full_response = ""
        token_count = 0

        async for chunk in llm.astream(search_context_messages):
            if chunk.content:
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
        llm = create_llm(provider)
        full_response = ""
        token_count = 0

        async for chunk in llm.astream(messages):
            if chunk.content:
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


async def get_history(app, thread_id: str) -> list[dict]:
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
