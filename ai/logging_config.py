"""Structured logging configuration using structlog + rich."""

import logging
import sys

import structlog
from rich.console import Console
from rich.traceback import install as install_rich_traceback

# Install rich traceback handler for beautiful exception formatting
install_rich_traceback(show_locals=True, width=120)

# Rich console for manual printing if needed
console = Console()


def setup_logging(*, json_logs: bool = False, log_level: str = "INFO") -> None:
    """Configure structlog with rich console output or JSON formatting.

    Args:
        json_logs: If True, output JSON logs (for production). Otherwise, rich console.
        log_level: Logging level (DEBUG, INFO, WARNING, ERROR).
    """
    # Shared processors for all configurations
    shared_processors: list[structlog.types.Processor] = [
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.UnicodeDecoder(),
    ]

    if json_logs:
        # Production: JSON output
        structlog.configure(
            processors=[
                *shared_processors,
                structlog.processors.format_exc_info,
                structlog.processors.JSONRenderer(),
            ],
            wrapper_class=structlog.make_filtering_bound_logger(
                getattr(logging, log_level.upper())
            ),
            context_class=dict,
            logger_factory=structlog.PrintLoggerFactory(),
            cache_logger_on_first_use=True,
        )
    else:
        # Development: Rich console output
        structlog.configure(
            processors=[
                *shared_processors,
                structlog.dev.ConsoleRenderer(
                    colors=True,
                    exception_formatter=structlog.dev.plain_traceback,
                ),
            ],
            wrapper_class=structlog.make_filtering_bound_logger(
                getattr(logging, log_level.upper())
            ),
            context_class=dict,
            logger_factory=structlog.PrintLoggerFactory(),
            cache_logger_on_first_use=True,
        )

    # Also configure standard library logging to use structlog
    logging.basicConfig(
        format="%(message)s",
        stream=sys.stdout,
        level=getattr(logging, log_level.upper()),
    )


def get_logger(name: str | None = None) -> structlog.stdlib.BoundLogger:
    """Get a logger instance.

    Args:
        name: Optional logger name (typically __name__).

    Returns:
        A bound structlog logger.
    """
    return structlog.get_logger(name)


# Convenience: pre-configured loggers for common modules
def get_server_logger() -> structlog.stdlib.BoundLogger:
    """Get logger for server module."""
    return get_logger("bro.server")


def get_graph_logger() -> structlog.stdlib.BoundLogger:
    """Get logger for graph module."""
    return get_logger("bro.graph")


def get_ws_logger() -> structlog.stdlib.BoundLogger:
    """Get logger for WebSocket connections."""
    return get_logger("bro.websocket")
