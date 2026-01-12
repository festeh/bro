"""Tests for DimaistCLI wrapper."""

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from agent.dimaist_cli import CLIError, DimaistCLI


class TestDimaistCLIInit:
    """Tests for DimaistCLI initialization."""

    def test_default_init(self):
        """Test initialization with defaults."""
        cli = DimaistCLI()
        assert cli._cli_path == "dimaist-cli"
        assert cli._timeout == 30.0

    def test_custom_path(self):
        """Test initialization with custom path."""
        cli = DimaistCLI(cli_path="/usr/local/bin/dimaist-cli")
        assert cli._cli_path == "/usr/local/bin/dimaist-cli"

    def test_custom_timeout(self):
        """Test initialization with custom timeout."""
        cli = DimaistCLI(timeout=60.0)
        assert cli._timeout == 60.0

    def test_env_path_override(self):
        """Test CLI path from environment variable."""
        with patch.dict("os.environ", {"DIMAIST_CLI_PATH": "/custom/path"}):
            cli = DimaistCLI()
            assert cli._cli_path == "/custom/path"


class TestDimaistCLIRun:
    """Tests for DimaistCLI.run() method."""

    @pytest.mark.asyncio
    async def test_run_success_dict(self):
        """Test successful CLI execution returning dict."""
        mock_proc = AsyncMock()
        mock_proc.communicate = AsyncMock(return_value=(b'{"id": 1, "title": "Test"}', b""))
        mock_proc.returncode = 0

        with patch("asyncio.create_subprocess_exec", return_value=mock_proc):
            cli = DimaistCLI()
            result = await cli.run("task", "get", "1")

            assert result == {"id": 1, "title": "Test"}

    @pytest.mark.asyncio
    async def test_run_success_list(self):
        """Test successful CLI execution returning list."""
        mock_proc = AsyncMock()
        mock_proc.communicate = AsyncMock(
            return_value=(b'[{"id": 1}, {"id": 2}]', b"")
        )
        mock_proc.returncode = 0

        with patch("asyncio.create_subprocess_exec", return_value=mock_proc):
            cli = DimaistCLI()
            result = await cli.run("task", "list")

            assert result == [{"id": 1}, {"id": 2}]

    @pytest.mark.asyncio
    async def test_run_empty_output(self):
        """Test CLI execution with empty output."""
        mock_proc = AsyncMock()
        mock_proc.communicate = AsyncMock(return_value=(b"", b""))
        mock_proc.returncode = 0

        with patch("asyncio.create_subprocess_exec", return_value=mock_proc):
            cli = DimaistCLI()
            result = await cli.run("task", "list")

            assert result == {}

    @pytest.mark.asyncio
    async def test_run_cli_not_found(self):
        """Test CLI not found error."""
        with patch(
            "asyncio.create_subprocess_exec",
            side_effect=FileNotFoundError("No such file"),
        ):
            cli = DimaistCLI(cli_path="/nonexistent/path")

            with pytest.raises(CLIError) as exc_info:
                await cli.run("task", "list")

            assert "CLI not found" in str(exc_info.value)
            assert exc_info.value.returncode == -1

    @pytest.mark.asyncio
    async def test_run_timeout(self):
        """Test CLI timeout error."""
        mock_proc = AsyncMock()
        mock_proc.kill = MagicMock()

        async def slow_communicate():
            await asyncio.sleep(10)
            return (b"", b"")

        mock_proc.communicate = slow_communicate

        with patch("asyncio.create_subprocess_exec", return_value=mock_proc):
            cli = DimaistCLI(timeout=0.01)

            with pytest.raises(CLIError) as exc_info:
                await cli.run("task", "list")

            assert "timeout" in str(exc_info.value).lower()
            mock_proc.kill.assert_called_once()

    @pytest.mark.asyncio
    async def test_run_nonzero_exit(self):
        """Test CLI command with non-zero exit code."""
        mock_proc = AsyncMock()
        mock_proc.communicate = AsyncMock(return_value=(b"", b"Task not found"))
        mock_proc.returncode = 1

        with patch("asyncio.create_subprocess_exec", return_value=mock_proc):
            cli = DimaistCLI()

            with pytest.raises(CLIError) as exc_info:
                await cli.run("task", "get", "999")

            assert "Task not found" in str(exc_info.value)
            assert exc_info.value.returncode == 1

    @pytest.mark.asyncio
    async def test_run_invalid_json(self):
        """Test CLI returning invalid JSON."""
        mock_proc = AsyncMock()
        mock_proc.communicate = AsyncMock(return_value=(b"not valid json", b""))
        mock_proc.returncode = 0

        with patch("asyncio.create_subprocess_exec", return_value=mock_proc):
            cli = DimaistCLI()

            with pytest.raises(CLIError) as exc_info:
                await cli.run("task", "list")

            assert "Invalid JSON" in str(exc_info.value)


class TestDimaistCLIGetHelp:
    """Tests for DimaistCLI.get_help() method."""

    @pytest.mark.asyncio
    async def test_get_help_success(self):
        """Test getting CLI help text."""
        help_text = "Usage: dimaist-cli <command>\n\nCommands:\n  task  Manage tasks"
        mock_proc = AsyncMock()
        mock_proc.communicate = AsyncMock(return_value=(b"", help_text.encode()))
        mock_proc.returncode = 0

        with patch("asyncio.create_subprocess_exec", return_value=mock_proc):
            cli = DimaistCLI()
            result = await cli.get_help()

            assert "Usage:" in result
            assert "task" in result

    @pytest.mark.asyncio
    async def test_get_help_cli_not_found(self):
        """Test get_help when CLI not found."""
        with patch(
            "asyncio.create_subprocess_exec",
            side_effect=FileNotFoundError("No such file"),
        ):
            cli = DimaistCLI()
            result = await cli.get_help()

            assert "not available" in result


class TestDimaistCLICheckAvailable:
    """Tests for DimaistCLI.check_available() method."""

    @pytest.mark.asyncio
    async def test_check_available_success(self):
        """Test CLI availability check when available."""
        mock_proc = AsyncMock()
        mock_proc.communicate = AsyncMock(return_value=(b"[]", b""))
        mock_proc.returncode = 0

        with patch("asyncio.create_subprocess_exec", return_value=mock_proc):
            cli = DimaistCLI()
            result = await cli.check_available()

            assert result is True

    @pytest.mark.asyncio
    async def test_check_available_not_found(self):
        """Test CLI availability check when not found."""
        with patch(
            "asyncio.create_subprocess_exec",
            side_effect=FileNotFoundError("No such file"),
        ):
            cli = DimaistCLI()
            result = await cli.check_available()

            assert result is False


class TestCLIError:
    """Tests for CLIError exception."""

    def test_cli_error_message(self):
        """Test CLIError message."""
        error = CLIError("Command failed")
        assert str(error) == "Command failed"

    def test_cli_error_returncode(self):
        """Test CLIError returncode."""
        error = CLIError("Failed", returncode=2)
        assert error.returncode == 2

    def test_cli_error_default_returncode(self):
        """Test CLIError default returncode."""
        error = CLIError("Failed")
        assert error.returncode == 1
