"""Task agent for voice-controlled task management via Dimaist CLI.

Uses LangGraph app for state persistence via namespaced thread IDs.
The LLM handles conversation context, pending confirmations, and CLI command generation.
"""

import logging
from dataclasses import dataclass, field
from datetime import datetime

from dimaist_cli import DimaistCLI

logger = logging.getLogger("task-agent")


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
        raise NotImplementedError("Implement in Phase 2")

    async def _build_system_prompt(self) -> str:
        """Build system prompt with CLI help and date context."""
        cli_help = await self._cli.get_help()
        return f"""You are a task management assistant. Help users manage their tasks via voice.

Current date: {self.today}
Current time: {self.current_datetime}

Available CLI commands:
{cli_help}

Guidelines:
- For any action that modifies tasks (create/update/complete/delete), propose the action and wait for user confirmation
- Parse natural language dates relative to current date
- If a request is ambiguous, ask for clarification
- Keep responses concise for voice
- When user says "no" or "never mind" to "anything else?", exit the task flow
"""
