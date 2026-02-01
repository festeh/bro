"""Basidian agent for voice-controlled notes and file management.

Uses BasidianClient HTTP API directly (no CLI subprocess).
The LLM interprets user intent and generates operations to execute.
"""

from __future__ import annotations

import json
import logging
import os
from dataclasses import dataclass, field
from datetime import datetime
from enum import StrEnum
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from langchain_openai import ChatOpenAI

from basidian.client import BasidianClient
from langchain_core.messages import AIMessage, HumanMessage, SystemMessage
from pydantic import BaseModel, Field

from agent.constants import get_basidian_url
from ai.llm_logging import get_llm_callbacks
from ai.models_config import create_chat_llm, get_llm_by_model_id

logger = logging.getLogger("basidian-agent")

LLMMessage = SystemMessage | HumanMessage | AIMessage


class Action(StrEnum):
    NONE = "none"
    QUERY = "query"
    WRITE = "write"
    EXIT = "exit"


class Operation(StrEnum):
    SEARCH_NOTES = "search_notes"
    SEARCH_FILES = "search_files"
    GET_TREE = "get_tree"
    READ_FILE = "read_file"
    RECENT = "recent"
    CREATE_FILE = "create_file"
    UPDATE_FILE = "update_file"
    DELETE_FILE = "delete_file"


class BasidianAgentOutput(BaseModel):
    """Structured output from LLM for basidian agent decisions."""

    response: str = Field(description="Text response to speak to the user")
    action: Action = Field(
        description=(
            "Action to take: "
            "'none' for general conversation or clarification, "
            "'query' for read-only operations (search, list, read), "
            "'write' for mutations (create, update, delete), "
            "'exit' to end the notes session"
        )
    )
    operation: Operation | None = Field(
        default=None,
        description="Which operation to execute (required for query/write actions)",
    )
    args: dict[str, Any] | None = Field(
        default=None,
        description=(
            "Operation arguments. Keys depend on operation: "
            "search_notes/search_files: {query}; "
            "get_tree: {} (no args); "
            "read_file: {path}; "
            "recent: {limit?}; "
            "create_file: {path, content, type?}; "
            "update_file: {path, content}; "
            "delete_file: {path}"
        ),
    )


@dataclass
class AgentResponse:
    """Response from basidian agent to main agent."""

    text: str
    exit_reason: str | None = None
    history_context: str | None = None

    @property
    def should_exit(self) -> bool:
        return self.exit_reason is not None

    @property
    def history_text(self) -> str:
        if self.history_context:
            return f"{self.history_context}\n\n{self.text}"
        return self.text


@dataclass
class Message:
    role: str
    content: str


@dataclass
class BasidianAgentState:
    session_id: str
    messages: list[Message] = field(default_factory=list)
    active: bool = False


SYSTEM_PROMPT_TEMPLATE = """You are a notes and knowledge base assistant. Help users manage their notes and files via voice.

Current date: {today}
Current time: {now}

Available operations:

READ OPERATIONS (action="query"):
- search_notes: Search notes by title/content. Args: {{query: "search text"}}
- search_files: Search files by name/content. Args: {{query: "search text"}}
- get_tree: Show the full file/folder tree. No args needed.
- read_file: Read a file's content. Args: {{path: "/folder/file.txt"}}
- recent: List recently modified files. Args: {{limit: 10}} (optional, default 10)

WRITE OPERATIONS (action="write"):
- create_file: Create a new file or folder. Args: {{path: "/folder/file.txt", content: "text", type: "file"}} (type defaults to "file", use "folder" for folders)
- update_file: Update file content. Args: {{path: "/folder/file.txt", content: "new text"}}
- delete_file: Delete a file or folder. Args: {{path: "/folder/file.txt"}}

Guidelines:
- For reading/searching, use action="query" with the appropriate operation
- For creating/updating/deleting, use action="write" with the appropriate operation
- If the user's request is ambiguous, ask for clarification with action="none"
- When the user wants to end the notes session, use action="exit"
- Keep responses concise for voice
- Paths start with "/" (e.g., "/notes/meeting.md")
"""


class BasidianAgent:
    """Notes agent using BasidianClient HTTP API."""

    def __init__(self, session_id: str, model_id: str) -> None:
        if not get_llm_by_model_id(model_id):
            raise ValueError(f"Unknown model_id: {model_id!r}")
        self._session_id = session_id
        self._model_id = model_id
        self._base_url = get_basidian_url()
        self._state = BasidianAgentState(session_id=session_id)

    @property
    def is_active(self) -> bool:
        return self._state.active

    def activate(self) -> None:
        self._state.active = True

    def deactivate(self) -> None:
        self._state.active = False

    def set_model(self, model_id: str) -> None:
        if not get_llm_by_model_id(model_id):
            raise ValueError(f"Unknown model_id: {model_id!r}")
        self._model_id = model_id

    async def process_message(self, user_message: str) -> AgentResponse:
        self._state.messages.append(Message(role="user", content=user_message))

        system_prompt = self._build_system_prompt()
        llm_messages: list[LLMMessage] = [SystemMessage(content=system_prompt)]
        for msg in self._state.messages:
            if msg.role == "user":
                llm_messages.append(HumanMessage(content=msg.content))
            else:
                llm_messages.append(AIMessage(content=msg.content))

        try:
            output = await self._call_llm(llm_messages)
        except Exception as e:
            logger.error(f"LLM call failed: {e}")
            return AgentResponse(text="I'm having trouble processing that. Could you try again?")

        logger.info(
            f"LLM output: action={output.action}, op={output.operation}, "
            f"response={output.response[:100]}"
        )

        response = await self._handle_action(output)
        self._state.messages.append(Message(role="assistant", content=response.history_text))
        return response

    async def _call_llm(self, messages: list[LLMMessage]) -> BasidianAgentOutput:
        llm = self._get_llm("basidian.process")
        structured_llm = llm.with_structured_output(
            BasidianAgentOutput, method="function_calling"
        )
        result = await structured_llm.ainvoke(messages)
        if not isinstance(result, BasidianAgentOutput):
            raise TypeError(f"Unexpected LLM output type: {type(result)}")
        return result

    def _get_llm(self, context: str = "basidian") -> ChatOpenAI:
        return create_chat_llm(self._model_id, callbacks=get_llm_callbacks(context))

    def _build_system_prompt(self) -> str:
        now = datetime.now().astimezone()
        return SYSTEM_PROMPT_TEMPLATE.format(
            today=now.strftime("%Y-%m-%d"),
            now=now.strftime("%Y-%m-%d %H:%M"),
        )

    async def _handle_action(self, output: BasidianAgentOutput) -> AgentResponse:
        match output.action:
            case Action.NONE:
                return AgentResponse(text=output.response)

            case Action.QUERY:
                if not output.operation or not output.args and output.operation != Operation.GET_TREE:
                    return AgentResponse(text=output.response)
                return await self._execute_operation(output)

            case Action.WRITE:
                if not output.operation:
                    return AgentResponse(text=output.response)
                return await self._execute_operation(output)

            case Action.EXIT:
                self.deactivate()
                return AgentResponse(text=output.response, exit_reason="user_exit")

            case _:
                return AgentResponse(text=output.response)

    async def _execute_operation(self, output: BasidianAgentOutput) -> AgentResponse:
        args = output.args or {}
        try:
            async with BasidianClient(self._base_url) as client:
                result = await self._run_operation(client, output.operation, args)
        except Exception as e:
            logger.error(f"Basidian operation failed: {e}")
            return AgentResponse(text=f"Operation failed: {e}")

        # For queries, summarize the results
        if output.action == Action.QUERY:
            summary = await self._summarize_results(result)
            history_context = f"[Op: {output.operation} {args}]\n[Result: {json.dumps(result, default=str)[:2000]}]"
            return AgentResponse(text=summary, history_context=history_context)

        # For writes, use the LLM's response
        return AgentResponse(text=output.response)

    async def _run_operation(
        self, client: BasidianClient, operation: Operation | None, args: dict[str, Any]
    ) -> Any:
        match operation:
            case Operation.SEARCH_NOTES:
                notes = await client.search_notes(args.get("query", ""))
                return [n.model_dump() for n in notes]

            case Operation.SEARCH_FILES:
                nodes = await client.search_files(args.get("query", ""))
                return [n.model_dump() for n in nodes]

            case Operation.GET_TREE:
                nodes = await client.get_tree()
                return [{"name": n.name, "path": n.path, "type": n.type} for n in nodes]

            case Operation.READ_FILE:
                node = await client.get_node(args["path"])
                if not node:
                    return {"error": f"File not found: {args['path']}"}
                return {"path": node.path, "content": node.content, "type": node.type}

            case Operation.RECENT:
                nodes = await client.get_tree()
                files = [n for n in nodes if n.type == "file"]
                files.sort(key=lambda n: n.updated_at or "", reverse=True)
                limit = args.get("limit", 10)
                return [
                    {"path": n.path, "updated_at": n.updated_at}
                    for n in files[:limit]
                ]

            case Operation.CREATE_FILE:
                node_type = args.get("type", "file")
                node = await client.create_node(args["path"], node_type, args.get("content", ""))
                return {"created": node.path, "type": node.type}

            case Operation.UPDATE_FILE:
                node = await client.get_node(args["path"])
                if not node:
                    return {"error": f"File not found: {args['path']}"}
                updated = await client.update_node(node.id, args["content"])
                return {"updated": updated.path}

            case Operation.DELETE_FILE:
                node = await client.get_node(args["path"])
                if not node:
                    return {"error": f"File not found: {args['path']}"}
                await client.delete_node(node.id)
                return {"deleted": args["path"]}

            case _:
                return {"error": f"Unknown operation: {operation}"}

    async def _summarize_results(self, result: Any) -> str:
        if isinstance(result, dict) and "error" in result:
            return result["error"]

        if isinstance(result, list) and not result:
            return "Nothing found."

        result_text = json.dumps(result, default=str)
        if len(result_text) > 3000:
            result_text = result_text[:3000] + "... (truncated)"

        prompt = f"""Summarize these results in a brief, conversational response suitable for voice.
Be concise - just the key information.

Results:
{result_text}
"""
        llm = self._get_llm("basidian.summarize")
        response = await llm.ainvoke([HumanMessage(content=prompt)])
        return str(response.content)
