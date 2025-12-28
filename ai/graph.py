"""LangGraph chat graph with persistence."""

from typing import AsyncIterator, Optional

from langchain_openai import ChatOpenAI
from langgraph.checkpoint.sqlite.aio import AsyncSqliteSaver
from langgraph.graph import START, MessagesState, StateGraph

from config import get_provider_config, settings
from logging_config import get_graph_logger

log = get_graph_logger()


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
) -> AsyncIterator[str]:
    """Stream the AI response token by token."""
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

    # Stream with specified provider
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
