"""File logging setup for the test stand."""

import logging
import os
from pathlib import Path

import structlog

LOG_DIR = Path("/tmp/bro-logs")
LOG_FILE = LOG_DIR / "teststand.log"

# Add TRACE level below DEBUG
TRACE = 5
logging.addLevelName(TRACE, "TRACE")

# Noisy libraries that should only log at TRACE level
NOISY_LOGGERS = [
    "httpcore",
    "httpx",
    "urllib3",
    "openai",
    "openai._base_client",
    "anthropic",
    "anthropic._base_client",
    "langchain_core",
    "langsmith",
]


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
    numeric_level = TRACE if log_level.upper() == "TRACE" else getattr(logging, log_level.upper())
    logging.basicConfig(
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        datefmt="%H:%M:%S",
        level=numeric_level,
        handlers=[logging.FileHandler(LOG_FILE, mode="a")],
        force=True,
    )

    # Set noisy loggers to TRACE (they only show if log level is TRACE)
    for logger_name in NOISY_LOGGERS:
        logging.getLogger(logger_name).setLevel(TRACE)

    return LOG_FILE


def set_log_level(log_level: str) -> None:
    """Change the log level dynamically.

    Args:
        log_level: One of TRACE, DEBUG, INFO
    """
    numeric_level = TRACE if log_level.upper() == "TRACE" else getattr(logging, log_level.upper())

    # Reconfigure structlog
    structlog.configure(
        wrapper_class=structlog.make_filtering_bound_logger(numeric_level),
        cache_logger_on_first_use=False,
    )

    # Reconfigure root logger
    logging.getLogger().setLevel(numeric_level)

    # Noisy loggers always stay at TRACE
    for logger_name in NOISY_LOGGERS:
        logging.getLogger(logger_name).setLevel(TRACE)


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
