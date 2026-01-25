"""Task agent for voice-controlled task management via Dimaist CLI.

Uses LangGraph app for state persistence via namespaced thread IDs.
The LLM handles conversation context, pending confirmations, and CLI command generation.
"""

import logging
from dataclasses import dataclass, field
from datetime import datetime
from enum import StrEnum
from typing import TypeVar

from langchain_core.messages import AIMessage, HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI
from pydantic import BaseModel, Field

from agent.constants import MAX_CLI_RETRIES
from agent.dimaist_cli import DimaistCLI
from ai.models_config import get_provider

# Result type for flat error handling (mirrors voice_agent.py)
T = TypeVar("T")


@dataclass
class Ok[T]:
    """Success result."""
    value: T


@dataclass
class Err:
    """Error result."""
    error: str


Result = Ok[T] | Err

logger = logging.getLogger("task-agent")


class Action(StrEnum):
    """Task agent action types."""

    NONE = "none"
    PROPOSE = "propose"
    CONFIRM = "confirm"
    CANCEL = "cancel"
    QUERY = "query"
    EXIT = "exit"


class TaskAgentOutput(BaseModel):
    """Structured output from LLM for task agent decisions."""

    response: str = Field(description="Text response to speak to the user")
    action: Action = Field(
        description=(
            "Action to take: "
            "'none' for general conversation, "
            "'propose' to suggest a CLI command for user approval, "
            "'confirm' when user approves pending action, "
            "'cancel' when user declines pending action, "
            "'query' to execute a read-only CLI command immediately, "
            "'exit' to end the task management session"
        )
    )
    cli_args: list[str] | None = Field(
        default=None,
        description="CLI arguments for 'propose' or 'query' actions (e.g., ['task', 'list', '--due', 'today'])",
    )


@dataclass
class AgentResponse:
    """Response from task agent to main agent."""

    text: str
    """Text to speak to user via TTS."""

    exit_reason: str | None = None
    """If set, return control to main agent with this reason."""

    history_context: str | None = None
    """Additional context to store in history (CLI command, results, etc.)."""

    @property
    def should_exit(self) -> bool:
        """Whether to return control to main agent."""
        return self.exit_reason is not None

    @property
    def history_text(self) -> str:
        """Text to store in conversation history (includes context if available)."""
        if self.history_context:
            return f"{self.history_context}\n\n{self.text}"
        return self.text


@dataclass
class Message:
    """Conversation message."""

    role: str  # "user" or "assistant"
    content: str


@dataclass
class TaskAgentState:
    """Conversation state for task agent."""

    session_id: str
    messages: list[Message] = field(default_factory=list)
    active: bool = False
    pending_command: list[str] | None = None  # CLI args to execute on confirm


class TaskAgent:
    """Task agent for task management via Dimaist CLI.

    LLM interprets user intent, manages confirmations, and generates CLI commands.
    State is maintained in-memory for the session duration.
    """

    def __init__(
        self,
        session_id: str,
        cli_path: str | None = None,
        provider: str = "groq",
        model: str | None = "qwen/qwen3-32b",
    ) -> None:
        """Initialize task agent.

        Args:
            session_id: Session ID for this task agent instance
            cli_path: Path to dimaist-cli binary (default: from DIMAIST_CLI_PATH env)
            provider: LLM provider name (chutes, groq, openrouter, gemini)
            model: Model name override (None = use provider default)
        """
        self._session_id = session_id
        self._cli = DimaistCLI(cli_path)  # DimaistCLI reads from env if None
        self._state: TaskAgentState | None = TaskAgentState(session_id=session_id)
        self._last_cli_command: list[str] | None = None  # For REPL debugging
        self._last_cli_result: dict | list | None = None  # For REPL debugging
        self._provider = provider
        self._model = model

    @property
    def current_datetime(self) -> str:
        """Current date and time in local timezone (minute granularity)."""
        return datetime.now().astimezone().strftime("%Y-%m-%d %H:%M")

    @property
    def today(self) -> str:
        """Current date in YYYY-MM-DD format for CLI commands."""
        return datetime.now().strftime("%Y-%m-%d")

    @property
    def is_active(self) -> bool:
        """Whether the task agent is currently handling the conversation."""
        return self._state is not None and self._state.active

    def activate(self) -> None:
        """Activate the task agent to handle subsequent messages."""
        if self._state:
            self._state.active = True

    def deactivate(self) -> None:
        """Deactivate the task agent, returning control to intent classification."""
        if self._state:
            self._state.active = False

    @property
    def has_pending(self) -> bool:
        """Whether there's a command awaiting confirmation (for UI button state)."""
        return self._state is not None and self._state.pending_command is not None

    @property
    def provider(self) -> str:
        """Current LLM provider."""
        return self._provider

    @property
    def model(self) -> str:
        """Current model name (override or provider default)."""
        return self._model or "default"

    def set_model(self, provider: str, model: str) -> None:
        """Change provider and model. Keeps conversation history."""
        self._provider = provider
        self._model = model

    async def confirm(self) -> AgentResponse:
        """Execute pending command (button press - no LLM)."""
        if not self._state or not self._state.pending_command:
            return AgentResponse(text="Nothing to confirm.")

        try:
            await self._cli.run(*self._state.pending_command)
            self._state.pending_command = None
            return AgentResponse(text="Done! Anything else?")
        except Exception as e:
            logger.error(f"CLI command failed: {e}")
            self._state.pending_command = None
            return AgentResponse(text=f"Failed: {e}. What else can I help with?")

    async def decline(self) -> AgentResponse:
        """Cancel pending command (button press - no LLM)."""
        if not self._state:
            return AgentResponse(text="Nothing to cancel.")

        self._state.pending_command = None
        return AgentResponse(text="Cancelled. What would you like to do?")

    async def process_message(self, user_message: str) -> AgentResponse:
        """Process a user message within the task management context.

        Args:
            user_message: The user's spoken/transcribed input

        Returns:
            AgentResponse with text to speak and optional exit signal
        """
        if not self._state:
            return AgentResponse(text="Session not active.", exit_reason="no_session")

        # Add user message to history
        self._state.messages.append(Message(role="user", content=user_message))

        # Build messages for LLM
        system_prompt = await self._build_system_prompt()
        llm_messages = [SystemMessage(content=system_prompt)]

        for msg in self._state.messages:
            if msg.role == "user":
                llm_messages.append(HumanMessage(content=msg.content))
            else:
                llm_messages.append(AIMessage(content=msg.content))

        # Call LLM with structured output
        try:
            output = await self._call_llm(llm_messages)
        except Exception as e:
            logger.error(f"LLM call failed: {e}")
            return AgentResponse(
                text="I'm having trouble processing that. Could you try again?"
            )

        logger.info(
            f"LLM output: action={output.action}, cli_args={output.cli_args}, "
            f"response={output.response[:100]}{'...' if len(output.response) > 100 else ''}"
        )

        # Handle action and get actual response
        response = await self._handle_action(output)

        # Add assistant response to history (use history_text which includes context)
        # This ensures query results with task IDs are in context for follow-ups
        self._state.messages.append(Message(role="assistant", content=response.history_text))

        return response

    async def _call_llm(self, messages: list) -> TaskAgentOutput:
        """Call LLM with structured output.

        Isolated wrapper for langchain which lacks proper type stubs.
        Runtime type check ensures correct return type.
        """
        provider = get_provider(self._provider)
        llm = ChatOpenAI(
            base_url=provider.base_url,  # type: ignore[call-arg]
            api_key=provider.api_key,  # type: ignore[call-arg]
            model=self._model,  # type: ignore[call-arg]
        )
        structured_llm = llm.with_structured_output(
            TaskAgentOutput,
            method="function_calling",
        )
        result = await structured_llm.ainvoke(messages)
        if not isinstance(result, TaskAgentOutput):
            raise TypeError(f"Unexpected LLM output type: {type(result)}")
        return result

    def _get_llm(self) -> ChatOpenAI:
        """Get configured LLM instance."""
        provider = get_provider(self._provider)
        return ChatOpenAI(
            base_url=provider.base_url,  # type: ignore[call-arg]
            api_key=provider.api_key,  # type: ignore[call-arg]
            model=self._model,  # type: ignore[call-arg]
        )

    async def _summarize_query_results(self, result: dict | list, max_tasks: int = 20) -> str:
        """Summarize query results using LLM for natural language response."""
        import json

        # Format results for LLM
        if isinstance(result, list):
            if not result:
                return "No tasks found."
            total = len(result)
            limited = result[:max_tasks]
            result_text = json.dumps(limited, default=str)
            if total > max_tasks:
                result_text += f"\n(showing {max_tasks} of {total} tasks)"
        else:
            result_text = json.dumps(result, default=str)

        prompt = f"""Summarize these task query results in a brief, conversational response suitable for voice.
Be concise - just the key information. Don't repeat the full data, summarize it.

Query results:
{result_text}

Current date: {self.today}
"""
        llm = self._get_llm()
        messages = [HumanMessage(content=prompt)]
        response = await llm.ainvoke(messages)
        return str(response.content)

    async def _build_system_prompt(self) -> str:
        """Build system prompt with CLI help and date context."""
        cli_help = await self._cli.get_help()

        # Include pending command context if any
        pending_context = ""
        if self._state and self._state.pending_command:
            cmd = " ".join(self._state.pending_command)
            pending_context = f"""
PENDING ACTION awaiting user confirmation: {cmd}
Use action="confirm" if user approves, action="cancel" if user declines.
"""

        return f"""You are a task management assistant. Help users manage their tasks via voice.

Current date: {self.today}
Current time: {self.current_datetime}
{pending_context}
Available CLI commands:
{cli_help}

Guidelines:
- For modifications (create/update/complete/delete), use action="propose" with cli_args
- For read-only queries, use action="query" with cli_args
- If ambiguous, ask for clarification with action="none"
- When user wants to end the task session, use action="exit"
- Keep responses concise for voice
"""

    async def _try_cli(self, cli_args: list[str]) -> Result[dict | list]:
        """Single CLI attempt. Returns Ok(result) or Err(message)."""
        try:
            result = await self._cli.run(*cli_args)
            return Ok(result)
        except Exception as e:
            logger.warning(f"CLI failed: {e}")
            return Err(str(e))

    async def _fix_cli_args(
        self,
        cli_args: list[str],
        error: str,
        cli_help: str,
    ) -> list[str] | None:
        """Ask LLM to fix CLI args based on error. Returns corrected args or None."""

        class FixOutput(BaseModel):
            can_fix: bool = Field(description="Whether the error is fixable by adjusting the command")
            cli_args: list[str] | None = Field(description="Corrected CLI args, or None if unfixable")

        prompt = f"""The CLI command failed. Fix it if possible.

Command: {' '.join(cli_args)}
Error: {error}

Available CLI commands:
{cli_help}

If the error is fixable by adjusting the command, provide corrected cli_args.
If unfixable (e.g., task doesn't exist, permission error), set can_fix=false.
"""
        try:
            llm = self._get_llm()
            structured_llm = llm.with_structured_output(FixOutput, method="function_calling")
            result = await structured_llm.ainvoke([HumanMessage(content=prompt)])
            if isinstance(result, FixOutput) and result.can_fix and result.cli_args:
                logger.info(f"LLM suggested fix: {result.cli_args}")
                return result.cli_args
        except Exception as e:
            logger.warning(f"LLM fix failed: {e}")

        return None

    async def _run_cli_with_retry(self, cli_args: list[str]) -> Result[dict | list]:
        """Run CLI command with LLM-assisted retry on failure."""
        cli_help = await self._cli.get_help()

        for attempt in range(MAX_CLI_RETRIES):
            result = await self._try_cli(cli_args)

            match result:
                case Ok(_):
                    return result
                case Err(error) if attempt == MAX_CLI_RETRIES - 1:
                    return Err(error)
                case Err(error):
                    logger.info(f"Retry {attempt + 1}/{MAX_CLI_RETRIES}: fixing CLI args")
                    fixed = await self._fix_cli_args(cli_args, error, cli_help)
                    if not fixed:
                        return Err(error)
                    cli_args = fixed

        return Err("Max retries exceeded")

    async def _handle_action(self, output: TaskAgentOutput) -> AgentResponse:
        """Handle the LLM's action decision."""
        self._last_cli_command = None  # Reset for this action
        self._last_cli_result = None

        if not self._state:
            return AgentResponse(text="Session error.", exit_reason="no_session")

        match output.action:
            case Action.NONE:
                # General conversation, no CLI action
                return AgentResponse(text=output.response)

            case Action.PROPOSE:
                # Set pending command for user approval
                if output.cli_args:
                    self._state.pending_command = output.cli_args
                    logger.info(f"Pending command set: {output.cli_args}")
                return AgentResponse(text=output.response)

            case Action.CONFIRM:
                # User confirmed - execute pending command with retry
                if not self._state.pending_command:
                    return AgentResponse(text="Nothing to confirm. What would you like to do?")

                self._last_cli_command = self._state.pending_command
                result = await self._run_cli_with_retry(self._state.pending_command)
                self._state.pending_command = None

                match result:
                    case Err(error):
                        return AgentResponse(text=f"Command failed: {error}. What else?")
                    case Ok(data):
                        logger.info(f"Command executed successfully: {data}")
                        return AgentResponse(text=output.response)

            case Action.CANCEL:
                # User declined - clear pending command
                self._state.pending_command = None
                return AgentResponse(text=output.response)

            case Action.QUERY:
                # Execute read-only command with retry
                if not output.cli_args:
                    return AgentResponse(text=output.response)

                import json

                self._last_cli_command = output.cli_args
                result = await self._run_cli_with_retry(output.cli_args)

                match result:
                    case Err(error):
                        return AgentResponse(text=f"Couldn't fetch tasks: {error}")
                    case Ok(data):
                        self._last_cli_result = data
                        if isinstance(data, list):
                            if not data:
                                return AgentResponse(text="No tasks found.")
                            logger.info(f"Query returned {len(data)} items")
                        summary = await self._summarize_query_results(data)
                        cli_cmd = " ".join(output.cli_args)
                        # Limit history to avoid bloating conversation context
                        limited = data[:20] if isinstance(data, list) else data
                        result_json = json.dumps(limited, default=str)
                        history_context = f"[CLI: {cli_cmd}]\n[Result: {result_json}]"
                        return AgentResponse(text=summary, history_context=history_context)

            case Action.EXIT:
                # End task management session
                self.deactivate()
                return AgentResponse(text=output.response, exit_reason="user_exit")

            case _:
                return AgentResponse(text=output.response)
