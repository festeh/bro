import asyncio
import json
import logging
import time
import uuid
from collections.abc import AsyncIterable

from livekit import rtc
from livekit.agents import Agent, StopResponse, llm
from livekit.agents.voice import ModelSettings
from livekit.plugins import elevenlabs

from agent.constants import (
    ATTR_INTENT,
    ATTR_MODEL,
    ATTR_RESPONSE_TYPE,
    ATTR_SEGMENT_ID,
    ATTR_TRANSCRIPTION_FINAL,
    TOPIC_LLM_STREAM,
    TOPIC_VAD_STATUS,
)
from agent.notes.basidian_agent import BasidianAgent
from agent.result import Err, Ok, Result
from agent.settings import (
    SESSION_TIMEOUT,
    SESSION_WARNING_THRESHOLD,
    AgentSettings,
    NotificationType,
    create_llm,
    create_stt,
)
from agent.task.task_agent import TaskAgent
from ai.graph import classify_intent
from ai.models import Intent
from ai.models_config import create_chat_llm

logger = logging.getLogger("voice-agent")


class ChatAgent(Agent):
    """Chat mode: STT → LLM → TTS with auto turn detection and immediate text streaming"""

    def __init__(self, settings: AgentSettings):
        super().__init__(
            instructions="You are a helpful voice assistant. Keep responses concise and conversational.",
            stt=create_stt(settings.stt_provider),
            llm=create_llm(settings.llm_model),
            tts=elevenlabs.TTS() if settings.tts_enabled else None,
        )
        self._settings = settings
        self._room: rtc.Room | None = None
        self._immediate_writer: rtc.TextStreamWriter | None = None
        self._segment_id: str = ""
        self._session_id: str = ""
        self._last_activity_time: float | None = None
        self._session_warning_sent: bool = False
        self._session_monitor_task: asyncio.Task[None] | None = None
        self._task_agent: TaskAgent | None = None
        self._basidian_agent: BasidianAgent | None = None
        # Response metadata for current stream
        self._current_intent: str | None = None
        self._current_response_type: str = "llm_response"

    def set_room(self, room: rtc.Room):
        """Set room reference for immediate text streaming."""
        self._room = room

    async def transcription_node(
        self,
        text: AsyncIterable[str],
        model_settings: ModelSettings,
    ) -> AsyncIterable[str]:
        """Stream text immediately while also passing through for TTS sync."""
        self._segment_id = f"LLM_{uuid.uuid4().hex[:8]}"

        async for chunk in text:
            # Send immediately via separate topic
            if self._room and chunk:
                await self._send_immediate(chunk)
            # Also yield for normal synced flow
            yield chunk

        # Flush immediate stream
        await self._flush_immediate()

    async def _send_immediate(self, text: str):
        """Send text chunk immediately to room."""
        if not self._room:
            return

        if not self._immediate_writer:
            attrs = {
                ATTR_SEGMENT_ID: self._segment_id,
                ATTR_TRANSCRIPTION_FINAL: "false",
                ATTR_RESPONSE_TYPE: self._current_response_type,
                ATTR_MODEL: self._settings.llm_model,
            }
            if self._current_intent:
                attrs[ATTR_INTENT] = self._current_intent
            self._immediate_writer = await self._room.local_participant.stream_text(
                topic=TOPIC_LLM_STREAM,
                attributes=attrs,
            )

        await self._immediate_writer.write(text)

    async def _flush_immediate(self):
        """Mark immediate stream as complete."""
        if self._immediate_writer:
            await self._immediate_writer.aclose()
            self._immediate_writer = None

    async def _send_session_notification(self, msg_type: NotificationType, **payload) -> None:
        """Send session notification to frontend via LiveKit data topic."""
        if not self._room:
            return
        msg = json.dumps(
            {
                "type": msg_type,
                "session_id": self._session_id,
                "timestamp": time.time(),
                **payload,
            }
        )
        try:
            writer = await self._room.local_participant.stream_text(topic=TOPIC_VAD_STATUS)
            await writer.write(msg)
            await writer.aclose()
            logger.debug(f"Session notification sent: {msg_type}")
        except Exception as e:
            logger.warning(f"Failed to send session notification: {e}")

    def start_session_timer(self) -> None:
        """Start session inactivity timer when audio track is subscribed."""
        self._session_id = f"session_{uuid.uuid4().hex[:8]}"
        self._last_activity_time = time.time()
        self._session_warning_sent = False
        if self._session_monitor_task:
            self._session_monitor_task.cancel()
        self._session_monitor_task = asyncio.create_task(self._monitor_session_timeout())
        logger.info(f"Session timer started: {self._session_id}")

    def stop_session_timer(self) -> None:
        """Stop session timer when audio track is unsubscribed."""
        if self._session_monitor_task:
            self._session_monitor_task.cancel()
            self._session_monitor_task = None
        logger.info(f"Session timer stopped: {self._session_id}")

    def on_turn_completed(self) -> None:
        """Reset inactivity timer when user completes a turn."""
        self._last_activity_time = time.time()
        self._session_warning_sent = False
        logger.debug(f"Turn completed, timer reset: {self._session_id}")

    async def _monitor_session_timeout(self) -> None:
        """Background task to monitor session inactivity and enforce timeout."""
        try:
            while True:
                await asyncio.sleep(0.5)
                if not self._last_activity_time:
                    break

                elapsed = time.time() - self._last_activity_time

                # Send warning at 55s of inactivity
                if elapsed >= SESSION_WARNING_THRESHOLD and not self._session_warning_sent:
                    remaining = int(SESSION_TIMEOUT - elapsed)
                    await self._send_session_notification(
                        NotificationType.SESSION_WARNING, remaining_seconds=remaining
                    )
                    self._session_warning_sent = True
                    logger.info(f"Session warning: {remaining}s remaining")

                # Timeout at 60s of inactivity
                if elapsed >= SESSION_TIMEOUT:
                    await self._send_session_notification(
                        NotificationType.SESSION_TIMEOUT,
                        reason="inactivity",
                        idle_duration=elapsed,
                    )
                    logger.info(f"Session timeout after {elapsed:.1f}s of inactivity")
                    break
        except asyncio.CancelledError:
            pass

    async def _process_input(self, text: str) -> Result[str | None]:
        """Process user input. Returns Ok(response) or Ok(None) for default LLM, Err on failure."""

        task_agent_enabled = "task" not in self._settings.excluded_agents
        basidian_agent_enabled = "basidian" not in self._settings.excluded_agents

        # Active agents get all messages (if still enabled)
        if self._task_agent and self._task_agent.is_active and task_agent_enabled:
            self._current_intent = Intent.TASK_MANAGEMENT
            self._current_response_type = "task_response"
            return await self._route_to_task_agent(text)

        if self._basidian_agent and self._basidian_agent.is_active and basidian_agent_enabled:
            self._current_intent = Intent.NOTES
            self._current_response_type = "notes_response"
            return await self._route_to_basidian_agent(text)

        # Classify intent
        try:
            classification = await classify_intent(
                [("user", text)], model_id=self._settings.llm_model
            )
        except Exception as e:
            logger.error(f"Intent classification failed: {e}", exc_info=True)
            self._current_intent = None
            self._current_response_type = "error"
            return Err(f"Configuration error: {e}")

        logger.debug(
            f"Intent: {classification.intent} (confidence: {classification.confidence:.2f})"
        )

        # Store intent for response metadata
        self._current_intent = classification.intent
        self._current_response_type = "llm_response"

        # Route task management to task agent (if enabled)
        if classification.intent == Intent.TASK_MANAGEMENT and task_agent_enabled:
            self._current_response_type = "task_response"
            return await self._route_to_task_agent(text)

        # Route notes to basidian agent (if enabled)
        if classification.intent == Intent.NOTES and basidian_agent_enabled:
            self._current_response_type = "notes_response"
            return await self._route_to_basidian_agent(text)

        # Default LLM flow
        return Ok(None)

    async def _route_to_task_agent(self, text: str) -> Result[str | None]:
        """Route message to task agent."""
        if not self._task_agent:
            self._task_agent = TaskAgent(
                session_id=self._session_id,
                model_id=self._settings.llm_model,
            )
            logger.info("Created TaskAgent")

        # Activate so subsequent messages route here (e.g., "y" for confirmation)
        self._task_agent.activate()

        try:
            response = await self._task_agent.process_message(text)
        except Exception as e:
            logger.error(f"TaskAgent failed: {e}", exc_info=True)
            return Err("Sorry, I couldn't process that task request.")

        logger.info(f"TaskAgent response: {response.text[:100]}...")

        if response.should_exit:
            logger.info(f"TaskAgent exiting: {response.exit_reason}")
            self._task_agent = None

        return Ok(response.text)

    async def _route_to_basidian_agent(self, text: str) -> Result[str | None]:
        """Route message to basidian notes agent."""
        if not self._basidian_agent:
            self._basidian_agent = BasidianAgent(
                session_id=self._session_id,
                model_id=self._settings.llm_model,
            )
            logger.info("Created BasidianAgent")

        self._basidian_agent.activate()

        try:
            response = await self._basidian_agent.process_message(text)
        except Exception as e:
            logger.error(f"BasidianAgent failed: {e}", exc_info=True)
            return Err("Sorry, I couldn't process that notes request.")

        logger.info(f"BasidianAgent response: {response.text[:100]}...")

        if response.should_exit:
            logger.info(f"BasidianAgent exiting: {response.exit_reason}")
            self._basidian_agent = None

        return Ok(response.text)

    async def on_user_turn_completed(
        self, turn_ctx: llm.ChatContext, new_message: llm.ChatMessage
    ) -> None:
        """Handle voice input - route through shared processing."""
        user_text = new_message.text_content or ""
        result = await self._process_input(user_text)

        match result:
            case Err(error):
                await self._speak_and_stop(error)
            case Ok(None):
                pass  # Let default LLM flow continue
            case Ok(response) if response is not None:
                await self._speak_and_stop(response)

    async def _get_response(
        self, result: Result[str | None], user_input: str
    ) -> AsyncIterable[str]:
        """Get response chunks - pre-made or generated."""
        match result:
            case Err(error):
                yield error
            case Ok(None):
                async for chunk in self._generate_llm(user_input):
                    yield chunk
            case Ok(response) if response is not None:
                yield response

    async def _generate_llm(self, user_input: str) -> AsyncIterable[str]:
        """Generate response chunks from LLM."""
        try:
            llm_client = create_chat_llm(self._settings.llm_model)
        except ValueError:
            logger.error(f"Unknown model: {self._settings.llm_model}")
            yield f"Error: Unknown model '{self._settings.llm_model}'. Check configuration."
            return

        async for chunk in llm_client.astream([("user", user_input)]):
            if chunk.content and isinstance(chunk.content, str):
                yield chunk.content

    async def _send(self, chunks: AsyncIterable[str]) -> None:
        """Stream response chunks to frontend."""
        if not self._room:
            logger.warning("Cannot send: no room")
            return

        self._segment_id = f"RESP_{uuid.uuid4().hex[:8]}"
        attrs = {
            ATTR_SEGMENT_ID: self._segment_id,
            ATTR_TRANSCRIPTION_FINAL: "false",
            ATTR_RESPONSE_TYPE: self._current_response_type,
            ATTR_MODEL: self._settings.llm_model,
        }
        if self._current_intent:
            attrs[ATTR_INTENT] = self._current_intent
        writer = await self._room.local_participant.stream_text(
            topic=TOPIC_LLM_STREAM,
            attributes=attrs,
        )

        try:
            async for chunk in chunks:
                await writer.write(chunk)
        finally:
            await writer.aclose()

    async def _speak_and_stop(self, text: str) -> None:
        """Stream response and stop default voice flow."""
        await self._send(self._once(text))
        raise StopResponse()

    async def _once(self, text: str) -> AsyncIterable[str]:
        """Yield a single value as async iterable."""
        yield text
