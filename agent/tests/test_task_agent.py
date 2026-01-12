"""Tests for TaskAgent."""

from unittest.mock import AsyncMock, patch

import pytest

from agent.task_agent import (
    Action,
    AgentResponse,
    Message,
    TaskAgent,
    TaskAgentOutput,
    TaskAgentState,
)


class TestTaskAgentOutput:
    """Tests for TaskAgentOutput model."""

    def test_create_basic(self):
        """Test creating basic output."""
        output = TaskAgentOutput(
            response="Hello!",
            action=Action.NONE,
        )
        assert output.response == "Hello!"
        assert output.action == Action.NONE
        assert output.cli_args is None

    def test_create_with_cli_args(self):
        """Test creating output with CLI args."""
        output = TaskAgentOutput(
            response="I'll add that task.",
            action=Action.PROPOSE,
            cli_args=["task", "add", "Buy milk"],
        )
        assert output.cli_args == ["task", "add", "Buy milk"]


class TestAgentResponse:
    """Tests for AgentResponse dataclass."""

    def test_basic_response(self):
        """Test basic response without exit."""
        resp = AgentResponse(text="Hello!")
        assert resp.text == "Hello!"
        assert resp.exit_reason is None
        assert resp.should_exit is False

    def test_exit_response(self):
        """Test response with exit reason."""
        resp = AgentResponse(text="Goodbye!", exit_reason="user_exit")
        assert resp.should_exit is True
        assert resp.exit_reason == "user_exit"


class TestTaskAgentState:
    """Tests for TaskAgentState dataclass."""

    def test_default_state(self):
        """Test default state initialization."""
        state = TaskAgentState(session_id="test-123")
        assert state.session_id == "test-123"
        assert state.messages == []
        assert state.active is True
        assert state.pending_command is None

    def test_state_with_messages(self):
        """Test state with messages."""
        messages = [
            Message(role="user", content="Hello"),
            Message(role="assistant", content="Hi there!"),
        ]
        state = TaskAgentState(session_id="test", messages=messages)
        assert len(state.messages) == 2


class TestTaskAgentInit:
    """Tests for TaskAgent initialization."""

    def test_basic_init(self):
        """Test basic initialization."""
        agent = TaskAgent(session_id="test-session")
        assert agent._session_id == "test-session"
        assert agent._state is not None
        assert agent._state.session_id == "test-session"

    def test_custom_cli_path(self):
        """Test initialization with custom CLI path."""
        agent = TaskAgent(session_id="test", cli_path="/custom/path")
        assert agent._cli._cli_path == "/custom/path"


class TestTaskAgentProperties:
    """Tests for TaskAgent properties."""

    def test_is_active_true(self):
        """Test is_active when active."""
        agent = TaskAgent(session_id="test")
        assert agent.is_active is True

    def test_is_active_false(self):
        """Test is_active when inactive."""
        agent = TaskAgent(session_id="test")
        agent._state.active = False
        assert agent.is_active is False

    def test_is_active_no_state(self):
        """Test is_active with no state."""
        agent = TaskAgent(session_id="test")
        agent._state = None
        assert agent.is_active is False

    def test_has_pending_true(self):
        """Test has_pending when command pending."""
        agent = TaskAgent(session_id="test")
        agent._state.pending_command = ["task", "add", "Test"]
        assert agent.has_pending is True

    def test_has_pending_false(self):
        """Test has_pending when no command pending."""
        agent = TaskAgent(session_id="test")
        assert agent.has_pending is False

    def test_today_format(self):
        """Test today property format."""
        agent = TaskAgent(session_id="test")
        today = agent.today
        # Should be YYYY-MM-DD format
        assert len(today) == 10
        assert today[4] == "-"
        assert today[7] == "-"

    def test_current_datetime_format(self):
        """Test current_datetime is ISO format."""
        agent = TaskAgent(session_id="test")
        dt = agent.current_datetime
        # Should be ISO format with timezone
        assert "T" in dt
        assert "+" in dt or "-" in dt[-6:]


class TestTaskAgentConfirm:
    """Tests for TaskAgent.confirm() method."""

    @pytest.mark.asyncio
    async def test_confirm_no_pending(self):
        """Test confirm with no pending command."""
        agent = TaskAgent(session_id="test")
        result = await agent.confirm()
        assert "Nothing to confirm" in result.text

    @pytest.mark.asyncio
    async def test_confirm_success(self):
        """Test successful confirm."""
        agent = TaskAgent(session_id="test")
        agent._state.pending_command = ["task", "add", "Test task"]

        with patch.object(agent._cli, "run", new_callable=AsyncMock) as mock_run:
            mock_run.return_value = {"id": 1, "title": "Test task"}
            result = await agent.confirm()

            assert "Done" in result.text
            assert agent._state.pending_command is None
            mock_run.assert_called_once_with("task", "add", "Test task")

    @pytest.mark.asyncio
    async def test_confirm_failure(self):
        """Test confirm with CLI failure."""
        agent = TaskAgent(session_id="test")
        agent._state.pending_command = ["task", "add", "Test"]

        with patch.object(agent._cli, "run", new_callable=AsyncMock) as mock_run:
            mock_run.side_effect = Exception("CLI error")
            result = await agent.confirm()

            assert "Failed" in result.text
            assert agent._state.pending_command is None


class TestTaskAgentDecline:
    """Tests for TaskAgent.decline() method."""

    @pytest.mark.asyncio
    async def test_decline_no_state(self):
        """Test decline with no state."""
        agent = TaskAgent(session_id="test")
        agent._state = None
        result = await agent.decline()
        assert "Nothing to cancel" in result.text

    @pytest.mark.asyncio
    async def test_decline_clears_pending(self):
        """Test decline clears pending command."""
        agent = TaskAgent(session_id="test")
        agent._state.pending_command = ["task", "add", "Test"]
        result = await agent.decline()

        assert "Cancelled" in result.text
        assert agent._state.pending_command is None


class TestTaskAgentProcessMessage:
    """Tests for TaskAgent.process_message() method."""

    @pytest.mark.asyncio
    async def test_process_no_state(self):
        """Test process_message with no state."""
        agent = TaskAgent(session_id="test")
        agent._state = None
        result = await agent.process_message("Hello")

        assert "not active" in result.text.lower()
        assert result.should_exit is True

    @pytest.mark.asyncio
    async def test_process_adds_message_to_history(self):
        """Test that process_message adds user message to history."""
        agent = TaskAgent(session_id="test")

        mock_output = TaskAgentOutput(
            response="Hi there!",
            action=Action.NONE,
        )

        with patch.object(agent, "_call_llm", new_callable=AsyncMock) as mock_llm:
            mock_llm.return_value = mock_output
            with patch.object(agent, "_build_system_prompt", new_callable=AsyncMock) as mock_prompt:
                mock_prompt.return_value = "System prompt"
                await agent.process_message("Hello")

        assert len(agent._state.messages) == 2
        assert agent._state.messages[0].role == "user"
        assert agent._state.messages[0].content == "Hello"
        assert agent._state.messages[1].role == "assistant"

    @pytest.mark.asyncio
    async def test_process_llm_error(self):
        """Test process_message handles LLM errors."""
        agent = TaskAgent(session_id="test")

        with patch.object(agent, "_call_llm", new_callable=AsyncMock) as mock_llm:
            mock_llm.side_effect = Exception("API error")
            with patch.object(agent, "_build_system_prompt", new_callable=AsyncMock) as mock_prompt:
                mock_prompt.return_value = "System prompt"
                result = await agent.process_message("Hello")

        assert "trouble processing" in result.text.lower()


class TestTaskAgentHandleAction:
    """Tests for TaskAgent._handle_action() method."""

    @pytest.mark.asyncio
    async def test_handle_action_none(self):
        """Test handling NONE action."""
        agent = TaskAgent(session_id="test")
        output = TaskAgentOutput(response="Hello!", action=Action.NONE)

        result = await agent._handle_action(output)

        assert result.text == "Hello!"
        assert result.should_exit is False

    @pytest.mark.asyncio
    async def test_handle_action_propose(self):
        """Test handling PROPOSE action."""
        agent = TaskAgent(session_id="test")
        output = TaskAgentOutput(
            response="I'll add that task for you.",
            action=Action.PROPOSE,
            cli_args=["task", "add", "Buy milk"],
        )

        result = await agent._handle_action(output)

        assert result.text == "I'll add that task for you."
        assert agent._state.pending_command == ["task", "add", "Buy milk"]

    @pytest.mark.asyncio
    async def test_handle_action_confirm_with_pending(self):
        """Test handling CONFIRM action with pending command."""
        agent = TaskAgent(session_id="test")
        agent._state.pending_command = ["task", "add", "Test"]

        output = TaskAgentOutput(response="Done!", action=Action.CONFIRM)

        with patch.object(agent._cli, "run", new_callable=AsyncMock) as mock_run:
            mock_run.return_value = {"id": 1}
            result = await agent._handle_action(output)

        assert result.text == "Done!"
        assert agent._state.pending_command is None

    @pytest.mark.asyncio
    async def test_handle_action_confirm_no_pending(self):
        """Test handling CONFIRM action without pending command."""
        agent = TaskAgent(session_id="test")
        output = TaskAgentOutput(response="Confirming...", action=Action.CONFIRM)

        result = await agent._handle_action(output)

        assert "Nothing to confirm" in result.text

    @pytest.mark.asyncio
    async def test_handle_action_cancel(self):
        """Test handling CANCEL action."""
        agent = TaskAgent(session_id="test")
        agent._state.pending_command = ["task", "add", "Test"]

        output = TaskAgentOutput(response="Cancelled.", action=Action.CANCEL)

        result = await agent._handle_action(output)

        assert result.text == "Cancelled."
        assert agent._state.pending_command is None

    @pytest.mark.asyncio
    async def test_handle_action_query(self):
        """Test handling QUERY action."""
        agent = TaskAgent(session_id="test")
        output = TaskAgentOutput(
            response="You have 3 tasks due today.",
            action=Action.QUERY,
            cli_args=["task", "list", "--due", "today"],
        )

        with patch.object(agent._cli, "run", new_callable=AsyncMock) as mock_run:
            mock_run.return_value = [{"id": 1}, {"id": 2}, {"id": 3}]
            result = await agent._handle_action(output)

        assert result.text == "You have 3 tasks due today."
        mock_run.assert_called_once_with("task", "list", "--due", "today")

    @pytest.mark.asyncio
    async def test_handle_action_query_empty(self):
        """Test handling QUERY action with empty results."""
        agent = TaskAgent(session_id="test")
        output = TaskAgentOutput(
            response="No tasks found.",
            action=Action.QUERY,
            cli_args=["task", "list"],
        )

        with patch.object(agent._cli, "run", new_callable=AsyncMock) as mock_run:
            mock_run.return_value = []
            result = await agent._handle_action(output)

        assert "No tasks found" in result.text

    @pytest.mark.asyncio
    async def test_handle_action_exit(self):
        """Test handling EXIT action."""
        agent = TaskAgent(session_id="test")
        output = TaskAgentOutput(response="Goodbye!", action=Action.EXIT)

        result = await agent._handle_action(output)

        assert result.text == "Goodbye!"
        assert result.should_exit is True
        assert result.exit_reason == "user_exit"
        assert agent._state.active is False


class TestAction:
    """Tests for Action enum."""

    def test_action_values(self):
        """Test Action enum values."""
        assert Action.NONE == "none"
        assert Action.PROPOSE == "propose"
        assert Action.CONFIRM == "confirm"
        assert Action.CANCEL == "cancel"
        assert Action.QUERY == "query"
        assert Action.EXIT == "exit"

    def test_action_is_string(self):
        """Test Action serializes as string."""
        assert str(Action.NONE) == "none"
        assert f"{Action.PROPOSE}" == "propose"
