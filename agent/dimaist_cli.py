"""Dimaist CLI wrapper for task management operations.

Executes dimaist-cli commands via subprocess and parses JSON output.
Returns raw dicts - no Python data model to keep in sync with CLI.
"""

import asyncio
import json
import logging
import os

from agent.constants import DIMAIST_CLI_PATH, TASK_AGENT_TIMEOUT

logger = logging.getLogger("dimaist-cli")


class CLIError(Exception):
    """CLI command failed."""

    def __init__(self, message: str, returncode: int = 1):
        super().__init__(message)
        self.returncode = returncode


class DimaistCLI:
    """Wrapper for dimaist-cli subprocess execution."""

    def __init__(
        self,
        cli_path: str | None = None,
        timeout: float | None = None,
    ) -> None:
        """Initialize CLI wrapper.

        Args:
            cli_path: Path to dimaist-cli binary (default: from constants)
            timeout: Command timeout in seconds (default: from constants)
        """
        self._cli_path = cli_path or os.getenv("DIMAIST_CLI_PATH", DIMAIST_CLI_PATH)
        self._timeout = timeout or TASK_AGENT_TIMEOUT

    async def run(self, *args: str) -> dict | list:
        """Execute CLI command and return parsed JSON.

        Args:
            *args: Command arguments (e.g., "task", "list")

        Returns:
            Parsed JSON output from stdout

        Raises:
            CLIError: Command failed or CLI not found
        """
        try:
            proc = await asyncio.create_subprocess_exec(
                self._cli_path,
                *args,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await asyncio.wait_for(
                proc.communicate(),
                timeout=self._timeout,
            )
        except FileNotFoundError:
            raise CLIError(f"CLI not found: {self._cli_path}", returncode=-1) from None
        except TimeoutError:
            proc.kill()
            raise CLIError(f"CLI timeout after {self._timeout}s", returncode=-1) from None

        if proc.returncode != 0:
            error_msg = stderr.decode().strip() or f"Exit code {proc.returncode}"
            raise CLIError(error_msg, returncode=proc.returncode or 1)

        output = stdout.decode().strip()
        logger.debug(f"CLI raw output: {output}")

        if not output:
            return {}

        try:
            return json.loads(output)
        except json.JSONDecodeError as e:
            logger.error(f"CLI raw output (parse failed): {output}")
            raise CLIError(f"Invalid JSON from CLI: {e}") from None

    async def get_help(self) -> str:
        """Get CLI help text for agent context.

        Returns:
            Help text from dimaist-cli (usage info)
        """
        try:
            proc = await asyncio.create_subprocess_exec(
                self._cli_path,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            _, stderr = await asyncio.wait_for(
                proc.communicate(),
                timeout=self._timeout,
            )
            # Help is printed to stderr
            return stderr.decode().strip()
        except (FileNotFoundError, TimeoutError):
            return "dimaist-cli not available"

    async def check_available(self) -> bool:
        """Check if CLI is available and working.

        Returns:
            True if CLI can be executed
        """
        try:
            await self.run("task", "list")
            return True
        except CLIError:
            return False
