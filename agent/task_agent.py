"""Task agent for voice-controlled task management via Dimaist CLI.

Uses LangGraph app for state persistence via namespaced thread IDs.
The LLM handles conversation context, pending confirmations, and CLI command generation.
"""

import logging
from dataclasses import dataclass, field
from datetime import datetime
from enum import StrEnum

from langchain_core.messages import AIMessage, HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI
from pydantic import BaseModel, Field

from agent.dimaist_cli import DimaistCLI
from ai.config import settings

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

    @property
    def should_exit(self) -> bool:
        """Whether to return control to main agent."""
        return self.exit_reason is not None


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
    active: bool = True
    pending_command: list[str] | None = None  # CLI args to execute on confirm


class TaskAgent:
    """Task agent for task management via Dimaist CLI.

    LLM interprets user intent, manages confirmations, and generates CLI commands.
    State is maintained in-memory for the session duration.
    """

    def __init__(
        self,
        session_id: str,
        cli_path: str = "dimaist-cli",
    ) -> None:
        """Initialize task agent.

        Args:
            session_id: Session ID for this task agent instance
            cli_path: Path to dimaist-cli binary
        """
        self._session_id = session_id
        self._cli = DimaistCLI(cli_path)
        self._state: TaskAgentState | None = TaskAgentState(session_id=session_id)

    @property
    def current_datetime(self) -> str:
        """Current date and time in local timezone (ISO format)."""
        return datetime.now().astimezone().isoformat()

    @property
    def today(self) -> str:
        """Current date in YYYY-MM-DD format for CLI commands."""
        return datetime.now().strftime("%Y-%m-%d")

    @property
    def is_active(self) -> bool:
        """Whether the task agent is currently handling the conversation."""
        return self._state is not None and self._state.active

    @property
    def has_pending(self) -> bool:
        """Whether there's a command awaiting confirmation (for UI button state)."""
        return self._state is not None and self._state.pending_command is not None

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

        logger.info(f"LLM output: action={output.action}, cli_args={output.cli_args}")

        # Add assistant response to history
        self._state.messages.append(Message(role="assistant", content=output.response))

        # Handle action
        return await self._handle_action(output)

    async def _call_llm(self, messages: list) -> TaskAgentOutput:
        """Call LLM with structured output.

        Isolated wrapper for langchain which lacks proper type stubs.
        Runtime type check ensures correct return type.
        """
        llm = ChatOpenAI(
            base_url=settings.llm_base_url,  # type: ignore[call-arg]
            api_key=settings.llm_api_key,  # type: ignore[call-arg]
            model=settings.llm_model,  # type: ignore[call-arg]
        )
        structured_llm = llm.with_structured_output(
            TaskAgentOutput,
            method="function_calling",
        )
        result = await structured_llm.ainvoke(messages)
        if not isinstance(result, TaskAgentOutput):
            raise TypeError(f"Unexpected LLM output type: {type(result)}")
        return result

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

    async def _handle_action(self, output: TaskAgentOutput) -> AgentResponse:
        """Handle the LLM's action decision."""
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
                # User confirmed - execute pending command
                if self._state.pending_command:
                    try:
                        result = await self._cli.run(*self._state.pending_command)
                        self._state.pending_command = None
                        logger.info(f"Command executed successfully: {result}")
                        return AgentResponse(text=output.response)
                    except Exception as e:
                        logger.error(f"CLI command failed: {e}")
                        self._state.pending_command = None
                        return AgentResponse(text=f"Command failed: {e}. What else?")
                return AgentResponse(text="Nothing to confirm. What would you like to do?")

            case Action.CANCEL:
                # User declined - clear pending command
                self._state.pending_command = None
                return AgentResponse(text=output.response)

            case Action.QUERY:
                # Execute read-only command immediately
                if output.cli_args:
                    try:
                        result = await self._cli.run(*output.cli_args)
                        # Format result for voice
                        if isinstance(result, list):
                            if not result:
                                return AgentResponse(text="No tasks found.")
                            # LLM already generated response, but we can enhance with data
                            logger.info(f"Query returned {len(result)} items")
                        return AgentResponse(text=output.response)
                    except Exception as e:
                        logger.error(f"Query failed: {e}")
                        return AgentResponse(text=f"Couldn't fetch tasks: {e}")
                return AgentResponse(text=output.response)

            case Action.EXIT:
                # End task management session
                self._state.active = False
                return AgentResponse(text=output.response, exit_reason="user_exit")

            case _:
                return AgentResponse(text=output.response)
