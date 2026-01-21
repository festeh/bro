"""Custom widgets for the test stand TUI."""

from textual.app import ComposeResult
from textual.containers import Vertical
from textual.message import Message
from textual.widget import Widget
from textual.widgets import Button, Input, RichLog, Static


class ChatMessage(Static):
    """A single message in the chat panel."""

    def __init__(self, content: str, msg_type: str = "user", **kwargs) -> None:
        super().__init__(**kwargs)
        self.content = content
        self.msg_type = msg_type

    def compose(self) -> ComposeResult:
        yield Static(self.content, classes=f"message {self.msg_type}")


class PendingAction(Widget):
    """Widget showing a pending action with confirm/decline buttons."""

    class Confirmed(Message):
        """Posted when user confirms the action."""

    class Declined(Message):
        """Posted when user declines the action."""

    def __init__(self, command: str, **kwargs) -> None:
        super().__init__(**kwargs)
        self.command = command

    def compose(self) -> ComposeResult:
        yield Static(f"[yellow]Pending:[/] {self.command}", classes="pending-command")
        with Vertical(classes="pending-buttons"):
            yield Button("Confirm (Y)", id="confirm-btn", variant="success")
            yield Button("Decline (N)", id="decline-btn", variant="error")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "confirm-btn":
            self.post_message(self.Confirmed())
        elif event.button.id == "decline-btn":
            self.post_message(self.Declined())


class RetryButton(Widget):
    """Widget showing a retry button after an error."""

    class Retry(Message):
        """Posted when user clicks retry."""

    def compose(self) -> ComposeResult:
        yield Button("Retry", id="retry-btn", variant="warning")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "retry-btn":
            self.post_message(self.Retry())


class ChatPanel(Widget):
    """The main chat panel with conversation history and input."""

    class MessageSubmitted(Message):
        """Posted when user submits a message."""

        def __init__(self, text: str) -> None:
            super().__init__()
            self.text = text

    def compose(self) -> ComposeResult:
        yield RichLog(id="chat-log", highlight=True, markup=True, wrap=True)
        yield Input(id="chat-input", placeholder="Type a message...")

    def on_input_submitted(self, event: Input.Submitted) -> None:
        if event.value.strip():
            self.post_message(self.MessageSubmitted(event.value))
            event.input.value = ""

    def add_message(self, content: str, style: str = "") -> None:
        """Add a message to the chat log."""
        log = self.query_one("#chat-log", RichLog)
        if style:
            log.write(f"[{style}]{content}[/{style}]")
        else:
            log.write(content)

    def add_user_message(self, text: str) -> None:
        """Add a user message."""
        self.add_message(f"[bold cyan]> {text}[/bold cyan]")

    def add_intent(self, intent: str, confidence: float) -> None:
        """Add intent classification result."""
        self.add_message(f"[dim][Intent] {intent} ({confidence:.0%})[/dim]")

    def add_router(self, route: str) -> None:
        """Add router decision."""
        self.add_message(f"[dim][Router] → {route}[/dim]")

    def add_response(self, text: str) -> None:
        """Add agent response."""
        self.add_message(f"[green]{text}[/green]")

    def add_error(self, text: str) -> None:
        """Add error message."""
        self.add_message(f"[bold red][Error] {text}[/bold red]")

    def add_pending(self, command: str) -> None:
        """Add pending action indicator."""
        self.add_message(f"[yellow][Pending] {command}[/yellow]")

    def clear(self) -> None:
        """Clear the chat log."""
        log = self.query_one("#chat-log", RichLog)
        log.clear()


class LogPanel(Widget):
    """The log panel showing tailed log file."""

    def compose(self) -> ComposeResult:
        yield Static("[bold]Logs[/bold]", classes="panel-header")
        yield RichLog(id="log-display", highlight=True, markup=True, wrap=True)

    def add_line(self, line: str) -> None:
        """Add a log line."""
        log = self.query_one("#log-display", RichLog)
        # Color errors red
        if "error" in line.lower():
            log.write(f"[red]{line}[/red]")
        elif "warning" in line.lower():
            log.write(f"[yellow]{line}[/yellow]")
        else:
            log.write(line)

    def clear(self) -> None:
        """Clear the log display."""
        log = self.query_one("#log-display", RichLog)
        log.clear()


class ParamsPanel(Widget):
    """The parameters panel showing current configuration."""

    def __init__(self, **kwargs) -> None:
        super().__init__(**kwargs)
        self._model = "groq/llama-3.3-70b"
        self._session_id = ""
        self._is_active = False
        self._pending = None

    def compose(self) -> ComposeResult:
        yield Static("[bold]Parameters[/bold]", classes="panel-header")
        yield Static(id="param-model")
        yield Static(id="param-session")
        yield Static(id="param-active")
        yield Static(id="param-pending")

    def on_mount(self) -> None:
        self._update_display()

    def _update_display(self) -> None:
        self.query_one("#param-model", Static).update(f"Model: {self._model}")
        self.query_one("#param-session", Static).update(f"Session: {self._session_id[:8]}...")
        active_str = "[green]Yes[/green]" if self._is_active else "[dim]No[/dim]"
        self.query_one("#param-active", Static).update(f"Active: {active_str}")
        pending_str = self._pending if self._pending else "[dim]None[/dim]"
        self.query_one("#param-pending", Static).update(f"Pending: {pending_str}")

    def set_model(self, model: str) -> None:
        self._model = model
        self._update_display()

    def set_session_id(self, session_id: str) -> None:
        self._session_id = session_id
        self._update_display()

    def set_active(self, is_active: bool) -> None:
        self._is_active = is_active
        self._update_display()

    def set_pending(self, pending: str | None) -> None:
        self._pending = pending
        self._update_display()
