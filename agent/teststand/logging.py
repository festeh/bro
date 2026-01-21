"""File logging setup for the test stand."""

import logging
import os
from pathlib import Path

import structlog

LOG_DIR = Path("/tmp/bro-logs")
LOG_FILE = LOG_DIR / "teststand.log"


def setup_file_logging(log_level: str = "DEBUG") -> Path:
    """Configure structlog to write to the test stand log file.

    Returns the path to the log file.
    """
    # Ensure log directory exists
    LOG_DIR.mkdir(parents=True, exist_ok=True)

    # Truncate log file on start
    LOG_FILE.write_text("")

    # Open file for writing
    log_file = open(LOG_FILE, "a")  # noqa: SIM115

    # Shared processors
    shared_processors: list[structlog.types.Processor] = [
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="%H:%M:%S"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.UnicodeDecoder(),
    ]

    # Configure structlog to write to file with plain text
    structlog.configure(
        processors=[
            *shared_processors,
            structlog.processors.format_exc_info,
            structlog.dev.ConsoleRenderer(colors=False),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(getattr(logging, log_level.upper())),
        context_class=dict,
        logger_factory=structlog.PrintLoggerFactory(file=log_file),
        cache_logger_on_first_use=False,  # Allow reconfiguration
    )

    # Also configure standard library logging
    logging.basicConfig(
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        datefmt="%H:%M:%S",
        level=getattr(logging, log_level.upper()),
        handlers=[logging.FileHandler(LOG_FILE, mode="a")],
        force=True,
    )

    return LOG_FILE


def get_log_file_path() -> Path:
    """Get the path to the log file."""
    return LOG_FILE


async def tail_log_file(callback, stop_event):
    """Tail the log file and call callback with new lines.

    Args:
        callback: Async function to call with each new line
        stop_event: asyncio.Event to signal when to stop
    """
    import asyncio

    import aiofiles

    # Wait for file to exist
    while not LOG_FILE.exists():
        if stop_event.is_set():
            return
        await asyncio.sleep(0.1)

    async with aiofiles.open(LOG_FILE) as f:
        # Seek to end
        await f.seek(0, os.SEEK_END)

        while not stop_event.is_set():
            line = await f.readline()
            if line:
                await callback(line.rstrip())
            else:
                await asyncio.sleep(0.1)
