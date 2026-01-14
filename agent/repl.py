"""Interactive REPL for testing the full agent pipeline.

Shows intent classification, routing decisions, and agent responses.

Usage:
    python -m agent.repl
    python agent/repl.py
"""

# ruff: noqa: E402
# Imports are ordered for initialization: dotenv must load before other modules

import logging
import os

from dotenv import load_dotenv

load_dotenv()
os.environ.setdefault("TRANSFORMERS_VERBOSITY", "error")

import structlog

structlog.configure(
    wrapper_class=structlog.make_filtering_bound_logger(logging.WARNING),
)

import asyncio
import sys
import uuid

from agent.dimaist_cli import DimaistCLI
from agent.task_agent import AgentResponse, TaskAgent
from ai.graph import classify_intent
from ai.models import Intent

# Provider aliases for /model command
PROVIDER_ALIASES = {
    "c": "chutes",
    "g": "groq",
    "o": "openrouter",
    "ge": "gemini",
    # Full names also work
    "chutes": "chutes",
    "groq": "groq",
    "openrouter": "openrouter",
    "gemini": "gemini",
}


def format_task_response(response: AgentResponse, agent: TaskAgent) -> str:
    """Format TaskAgent response with metadata."""
    lines = []

    # Show CLI command if one was executed
    if agent._last_cli_command:
        cmd = " ".join(agent._last_cli_command)
        lines.append(f"  cli: {cmd}")

    # Show CLI result if available
    if agent._last_cli_result is not None:
        result = agent._last_cli_result
        if isinstance(result, list):
            lines.append(f"  result: {len(result)} items")
            # Show first few items as summary
            for item in result[:5]:
                if isinstance(item, dict):
                    title = item.get("title", str(item))
                    lines.append(f"    - {title}")
            if len(result) > 5:
                lines.append(f"    ... and {len(result) - 5} more")
        else:
            lines.append(f"  result: {result}")

    lines.append(f"  response: {response.text}")

    state = agent._state
    if state and state.pending_command:
        cmd = " ".join(state.pending_command)
        lines.append(f"  pending: {cmd}")

    if response.exit_reason:
        lines.append(f"  exit_reason: {response.exit_reason}")

    return "\n".join(lines)


def print_banner(agent: TaskAgent) -> None:
    """Print startup banner and usage instructions."""
    print("=" * 60)
    print("Agent Test REPL")
    print("=" * 60)
    print()
    print("Messages go through intent classification, then route to")
    print("the appropriate handler (TaskAgent, web search, etc.)")
    print()
    print(f"Model: {agent.provider} / {agent.model}")
    print()
    print("Commands: /help, /model, /exit")
    print("Press Ctrl+C to exit at any time.")
    print("=" * 60)
    print()


def print_help() -> None:
    """Print help message."""
    print()
    print("Agent Test REPL - Help")
    print("-" * 40)
    print()
    print("This REPL shows the full agent pipeline:")
    print("  1. Intent classification (what type of request)")
    print("  2. Routing to appropriate handler")
    print("  3. Handler response")
    print()
    print("Intent types:")
    print("  - task_management: Routes to TaskAgent")
    print("  - direct_response: General conversation")
    print("  - web_search: Would search the web")
    print("  - end_dialog: Exits conversation")
    print()
    print("Commands:")
    print("  /help              - Show this help")
    print("  /exit              - Exit the REPL")
    print("  /model             - Show current provider and model")
    print("  /model <p> <model> - Switch provider and model")
    print()
    print("Provider aliases: c=chutes, g=groq, o=openrouter, ge=gemini")
    print()
    print("Examples:")
    print('  > add task buy groceries  (task_management)')
    print('  > what is the capital of France?  (direct_response)')
    print('  > /model c deepseek-ai/DeepSeek-V3-0324')
    print('  > /model g llama-3.3-70b-versatile')
    print()


def handle_command(command: str, agent: TaskAgent) -> bool:
    """Handle REPL command. Returns True if should exit."""
    parts = command.strip().split()
    cmd = parts[0].lower()

    if cmd == "/help":
        print_help()
        return False

    if cmd == "/exit":
        print("Goodbye!")
        return True

    if cmd == "/model":
        if len(parts) == 1:
            # Show current provider and model
            print(f"Provider: {agent.provider}")
            print(f"Model: {agent.model}")
            return False

        if len(parts) < 3:
            print("Usage: /model <provider> <model>")
            print("Provider aliases: c=chutes, g=groq, o=openrouter, ge=gemini")
            return False

        alias = parts[1].lower()
        model = parts[2]

        provider = PROVIDER_ALIASES.get(alias)
        if not provider:
            print(f"Unknown provider: {alias}")
            print("Provider aliases: c=chutes, g=groq, o=openrouter, ge=gemini")
            return False

        agent.set_model(provider, model)
        print(f"Switched to {provider} / {model}")
        return False

    print(f"Unknown command: {command}")
    print("Type /help for available commands.")
    return False


async def process_input(
    agent: TaskAgent,
    user_input: str,
    history: list[tuple[str, str]],
) -> bool:
    """Process user input through intent classification and routing.

    Returns True if REPL should exit.
    """
    print("Classifying...", end="", flush=True)

    try:
        # Build messages for classifier (includes history)
        messages = list(history) + [("user", user_input)]

        # Step 1: Classify intent
        classification = await classify_intent(messages, provider=agent.provider)

        # Clear status and show classification
        print("\r" + " " * 20 + "\r", end="")
        print(f"[Intent] {classification.intent} (confidence: {classification.confidence:.0%})")

        # Step 2: Route based on intent
        if classification.intent == Intent.TASK_MANAGEMENT:
            print("[Router] → TaskAgent")
            print("Processing...", end="", flush=True)

            response = await agent.process_message(user_input)

            print("\r" + " " * 20 + "\r", end="")
            print("[TaskAgent]")
            print(format_task_response(response, agent))
            print()

            # Add to history
            history.append(("user", user_input))
            history.append(("assistant", response.text))

            return response.should_exit

        elif classification.intent == Intent.END_DIALOG:
            print("[Router] → End dialog")
            print(f"[Response] {classification.response}")
            print()
            return True

        elif classification.intent == Intent.WEB_SEARCH:
            print(f"[Router] → Web search (query: {classification.search_query})")
            print(f"[Response] {classification.response}")
            print("  (web search not implemented in REPL)")
            print()

            history.append(("user", user_input))
            history.append(("assistant", classification.response))

        else:  # DIRECT_RESPONSE
            print("[Router] → Direct response")
            print(f"[Response] {classification.response}")
            print()

            history.append(("user", user_input))
            history.append(("assistant", classification.response))

    except Exception as e:
        print("\r" + " " * 20 + "\r", end="")
        print(f"[Error] {type(e).__name__}: {e}")
        print()

    return False


async def check_cli() -> bool:
    """Check if dimaist-cli is available. Returns True if OK."""
    cli = DimaistCLI()
    cli_path = cli._cli_path

    print(f"Checking CLI: {cli_path}")

    if not os.path.exists(cli_path) and "/" in cli_path:
        print(f"  ERROR: File not found: {cli_path}")
        return False

    available = await cli.check_available()
    if available:
        print("  OK: CLI is available")
        return True
    else:
        print("  ERROR: CLI not working (check DATABASE_URL and other env vars)")
        return False


async def run_repl() -> None:
    """Run the interactive REPL loop."""
    session_id = f"repl-{uuid.uuid4().hex[:8]}"
    agent = TaskAgent(session_id=session_id)

    print_banner(agent)

    # Sanity check CLI before starting
    if not await check_cli():
        print("\nFix the CLI configuration and try again.")
        return

    print()
    history: list[tuple[str, str]] = []

    while True:
        try:
            user_input = input("> ").strip()

            if not user_input:
                continue

            if user_input.startswith("/"):
                if handle_command(user_input, agent):
                    break
                continue

            should_exit = await process_input(agent, user_input, history)
            if should_exit:
                break

        except KeyboardInterrupt:
            print("\n\nInterrupted. Goodbye!")
            break

        except EOFError:
            print("\nGoodbye!")
            break


def main() -> None:
    """Entry point for the REPL."""
    try:
        asyncio.run(run_repl())
    except KeyboardInterrupt:
        print("\nGoodbye!")
        sys.exit(0)


if __name__ == "__main__":
    main()
