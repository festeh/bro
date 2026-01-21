"""Test Stand TUI - A Textual-based debug interface for the agent."""

import asyncio
import uuid

from textual import work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.screen import ModalScreen
from textual.widgets import Footer, Header, Static

from agent.task_agent import TaskAgent
from ai.graph import classify_intent
from ai.models import Intent

from .logging import get_log_file_path, setup_file_logging, tail_log_file
from .models import MODELS, Model, get_default_model, get_model_by_index
from .widgets import ChatPanel, LogPanel, ParamsPanel


class HelpScreen(ModalScreen):
    """Help overlay screen."""

    BINDINGS = [
        Binding("escape", "dismiss", "Close"),
        Binding("ctrl+h", "dismiss", "Close"),
    ]

    def compose(self) -> ComposeResult:
        yield Vertical(
            Static("[bold]Test Stand Help[/bold]\n", classes="help-title"),
            Static(
                "[bold]Keyboard Shortcuts[/bold]\n"
                "  Enter     Send message\n"
                "  Y         Confirm pending action\n"
                "  N         Decline pending action\n"
                "  Ctrl+M    Cycle through models\n"
                "  Ctrl+L    Clear all / new session\n"
                "  Ctrl+H    Show this help\n"
                "  Ctrl+C    Exit app\n"
            ),
            Static(
                "\n[bold]How It Works[/bold]\n"
                "  1. Type a message and press Enter\n"
                "  2. Intent is classified (task, search, etc.)\n"
                "  3. Message is routed to appropriate handler\n"
                "  4. Response is displayed\n"
            ),
            id="help-content",
        )

    def action_dismiss(self) -> None:
        self.app.pop_screen()


CSS = """
Screen {
    layout: horizontal;
}

#left-panel {
    width: 85%;
    height: 100%;
    layout: vertical;
}

#params-panel {
    width: 15%;
    height: 100%;
    border-left: solid $primary;
}

ChatPanel {
    height: 60%;
    layout: vertical;
}

#chat-log {
    height: 1fr;
    border: solid $secondary;
    padding: 0 1;
}

#chat-input {
    height: 3;
    dock: bottom;
}

LogPanel {
    height: 40%;
    layout: vertical;
    border-top: solid $primary;
}

#log-display {
    height: 1fr;
    border: solid $secondary;
    padding: 0 1;
}

ParamsPanel {
    height: 100%;
    layout: vertical;
    padding: 1;
}

.panel-header {
    height: 1;
    background: $primary-darken-2;
    padding: 0 1;
}

#help-content {
    width: 60;
    height: auto;
    border: solid $primary;
    background: $surface;
    padding: 1 2;
}

.help-title {
    text-align: center;
}
"""


class TestStandApp(App):
    """Test Stand TUI Application."""

    TITLE = "Agent Test Stand"
    CSS = CSS

    BINDINGS = [
        Binding("ctrl+c", "quit", "Exit", show=True),
        Binding("ctrl+m", "cycle_model", "Model", show=True),
        Binding("ctrl+l", "clear_all", "Clear", show=True),
        Binding("ctrl+h", "show_help", "Help", show=True),
        Binding("y", "confirm_pending", "Confirm", show=False),
        Binding("n", "decline_pending", "Decline", show=False),
    ]

    def __init__(self) -> None:
        super().__init__()
        self._model_index = 0
        self._current_model: Model = get_default_model()
        self._session_id = f"teststand-{uuid.uuid4().hex[:8]}"
        self._agent: TaskAgent | None = None
        self._history: list[tuple[str, str]] = []
        self._last_user_message: str = ""
        self._stop_log_tail = asyncio.Event()

    def compose(self) -> ComposeResult:
        yield Header()
        with Horizontal():
            with Vertical(id="left-panel"):
                yield ChatPanel()
                yield LogPanel(id="log-panel")
            yield ParamsPanel(id="params-panel")
        yield Footer()

    async def on_mount(self) -> None:
        """Initialize when app starts."""
        # Setup file logging
        setup_file_logging()

        # Create agent with current model
        self._agent = TaskAgent(
            session_id=self._session_id,
            provider=self._current_model.provider,
            model=self._current_model.model_id,
        )

        # Update params panel
        params = self.query_one(ParamsPanel)
        params.set_model(self._current_model.display_name)
        params.set_session_id(self._session_id)
        params.set_active(False)
        params.set_pending(None)

        # Start log tailing
        self._start_log_tail()

        # Focus the input
        self.query_one("#chat-input").focus()

    def _start_log_tail(self) -> None:
        """Start tailing the log file in the background."""
        self._stop_log_tail.clear()
        asyncio.create_task(self._tail_logs())

    async def _tail_logs(self) -> None:
        """Tail the log file and update the log panel."""
        log_panel = self.query_one(LogPanel)

        async def on_log_line(line: str) -> None:
            log_panel.add_line(line)

        await tail_log_file(on_log_line, self._stop_log_tail)

    def on_chat_panel_message_submitted(self, event: ChatPanel.MessageSubmitted) -> None:
        """Handle user message submission."""
        self._last_user_message = event.text
        self._process_message(event.text)

    @work(exclusive=True)
    async def _process_message(self, user_input: str) -> None:
        """Process user input through intent classification and routing."""
        chat = self.query_one(ChatPanel)
        params = self.query_one(ParamsPanel)

        chat.add_user_message(user_input)

        try:
            # If TaskAgent is active, route directly to it
            if self._agent.is_active:
                chat.add_router("TaskAgent (in context)")

                response = await self._agent.process_message(user_input)

                self._show_task_response(response)
                self._history.append(("user", user_input))
                self._history.append(("assistant", response.text))

                # Update params
                params.set_active(self._agent.is_active)
                params.set_pending(self._get_pending_command())
                return

            chat.add_message("[dim]Classifying...[/dim]")

            # Build messages for classifier
            messages = list(self._history) + [("user", user_input)]

            # Classify intent
            classification = await classify_intent(messages, provider=self._current_model.provider)

            chat.add_intent(classification.intent.value, classification.confidence)

            # Route based on intent
            if classification.intent == Intent.TASK_MANAGEMENT:
                chat.add_router("TaskAgent")
                self._agent.activate()

                response = await self._agent.process_message(user_input)

                self._show_task_response(response)
                self._history.append(("user", user_input))
                self._history.append(("assistant", response.text))

            elif classification.intent == Intent.END_DIALOG:
                chat.add_router("End dialog")
                chat.add_response(classification.response)

            elif classification.intent == Intent.WEB_SEARCH:
                chat.add_router(f"Web search ({classification.search_query})")
                chat.add_response(classification.response)
                chat.add_message("[dim](web search not implemented)[/dim]")
                self._history.append(("user", user_input))
                self._history.append(("assistant", classification.response))

            else:  # DIRECT_RESPONSE
                chat.add_router("Direct response")
                chat.add_response(classification.response)
                self._history.append(("user", user_input))
                self._history.append(("assistant", classification.response))

            # Update params
            params.set_active(self._agent.is_active)
            params.set_pending(self._get_pending_command())

        except Exception as e:
            chat.add_error(f"{type(e).__name__}: {e}")

    def _show_task_response(self, response) -> None:
        """Display TaskAgent response in chat."""
        chat = self.query_one(ChatPanel)

        # Show CLI command if executed
        if self._agent._last_cli_command:
            cmd = " ".join(self._agent._last_cli_command)
            chat.add_message(f"[dim]CLI: {cmd}[/dim]")

        # Show result summary
        if self._agent._last_cli_result is not None:
            result = self._agent._last_cli_result
            if isinstance(result, list):
                chat.add_message(f"[dim]Result: {len(result)} items[/dim]")

        # Show response
        chat.add_response(response.text)

        # Show pending if any
        if self._agent.has_pending:
            cmd = " ".join(self._agent._state.pending_command)
            chat.add_pending(cmd)

    def _get_pending_command(self) -> str | None:
        """Get the pending command string if any."""
        if self._agent and self._agent.has_pending:
            return " ".join(self._agent._state.pending_command)
        return None

    def action_cycle_model(self) -> None:
        """Cycle to the next model."""
        self._model_index = (self._model_index + 1) % len(MODELS)
        self._current_model = get_model_by_index(self._model_index)

        # Update agent
        self._agent.set_model(self._current_model.provider, self._current_model.model_id)

        # Update params panel
        params = self.query_one(ParamsPanel)
        params.set_model(self._current_model.display_name)

        # Show notification
        chat = self.query_one(ChatPanel)
        chat.add_message(f"[yellow]Switched to {self._current_model.display_name}[/yellow]")

    def action_clear_all(self) -> None:
        """Clear conversation and logs, start new session."""
        # Clear chat
        chat = self.query_one(ChatPanel)
        chat.clear()

        # Clear logs
        log_panel = self.query_one(LogPanel)
        log_panel.clear()

        # Also truncate log file
        log_file = get_log_file_path()
        log_file.write_text("")

        # New session
        self._session_id = f"teststand-{uuid.uuid4().hex[:8]}"
        self._agent = TaskAgent(
            session_id=self._session_id,
            provider=self._current_model.provider,
            model=self._current_model.model_id,
        )
        self._history = []

        # Update params
        params = self.query_one(ParamsPanel)
        params.set_session_id(self._session_id)
        params.set_active(False)
        params.set_pending(None)

        chat.add_message("[yellow]Session cleared. Starting fresh.[/yellow]")

    def action_show_help(self) -> None:
        """Show help overlay."""
        self.push_screen(HelpScreen())

    @work
    async def action_confirm_pending(self) -> None:
        """Confirm the pending action."""
        if not self._agent or not self._agent.has_pending:
            return

        chat = self.query_one(ChatPanel)
        params = self.query_one(ParamsPanel)

        response = await self._agent.confirm()
        chat.add_response(response.text)

        params.set_pending(self._get_pending_command())

    @work
    async def action_decline_pending(self) -> None:
        """Decline the pending action."""
        if not self._agent or not self._agent.has_pending:
            return

        chat = self.query_one(ChatPanel)
        params = self.query_one(ParamsPanel)

        response = self._agent.decline()
        chat.add_response(response.text)

        params.set_pending(None)

    async def on_unmount(self) -> None:
        """Cleanup when app exits."""
        self._stop_log_tail.set()


def main() -> None:
    """Entry point for the test stand."""
    # Load environment
    from dotenv import load_dotenv

    load_dotenv()

    app = TestStandApp()
    app.run()


if __name__ == "__main__":
    main()
