import asyncio
import json
import logging
import time
import uuid
from collections.abc import AsyncIterable
from dataclasses import dataclass, field
from enum import StrEnum
from typing import Generic, TypeVar

from dotenv import load_dotenv
from langchain_openai import ChatOpenAI
from livekit import rtc
from livekit.agents import (
    Agent,
    AgentServer,
    AgentSession,
    AutoSubscribe,
    JobContext,
    JobProcess,
    StopResponse,
    cli,
    llm,
    metrics,
    room_io,
)
from livekit.agents.voice import ModelSettings, UserStateChangedEvent
from livekit.plugins import deepgram, elevenlabs, openai, silero
from livekit.plugins.turn_detector.multilingual import MultilingualModel

from agent.constants import (
    ATTR_INTENT,
    ATTR_MODEL,
    ATTR_RESPONSE_TYPE,
    ATTR_SEGMENT_ID,
    ATTR_TRANSCRIPTION_FINAL,
    TOPIC_LLM_STREAM,
    TOPIC_TEXT_INPUT,
    TOPIC_VAD_STATUS,
)
from agent.task_agent import TaskAgent
from ai.graph import classify_intent
from ai.models import Intent
from ai.models_config import get_default_llm, get_llm_by_model_id

load_dotenv()

# Result type for error handling (like Rust's Result<T, E>)
T = TypeVar("T")


@dataclass
class Ok(Generic[T]):
    """Success result."""
    value: T


@dataclass
class Err:
    """Error result."""
    error: str


Result = Ok[T] | Err

# Session inactivity timeout
SESSION_TIMEOUT = 60.0  # seconds without completed turn
SESSION_WARNING_THRESHOLD = 55.0  # seconds


class NotificationType(StrEnum):
    """Session notification types."""

    SESSION_WARNING = "session_warning"
    SESSION_TIMEOUT = "session_timeout"
    SESSION_READY = "session_ready"

logger = logging.getLogger("voice-agent")


@dataclass
class AgentSettings:
    """Configuration for agent behavior."""

    stt_provider: str = "deepgram"
    llm_model: str = field(default_factory=lambda: get_default_llm().model_id)
    tts_enabled: bool = True
    task_agent_provider: str = "groq"
    agent_mode: str = "chat"

    @classmethod
    def from_dict(cls, d: dict) -> "AgentSettings":
        return cls(
            stt_provider=d.get("stt_provider", "deepgram"),
            llm_model=d.get("llm_model", get_default_llm().model_id),
            tts_enabled=d.get("tts_enabled", True),
            task_agent_provider=d.get("task_agent_provider", "groq"),
            agent_mode=d.get("agent_mode", "chat"),
        )


def create_stt(provider: str):
    """Create STT instance based on provider name."""
    if provider == "elevenlabs":
        return elevenlabs.STT()
    return deepgram.STT(model="nova-3")


def create_llm(model_id: str) -> openai.LLM | None:
    """Create LLM instance from model_id. Returns None if model not found."""
    model = get_llm_by_model_id(model_id)
    if not model:
        logger.error(f"Unknown model: {model_id}. Check models.json configuration.")
        return None

    return openai.LLM(
        model=model.model_id,
        base_url=model.base_url,
        api_key=model.api_key,
    )


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
        self._session_monitor_task: asyncio.Task | None = None
        self._task_agent: TaskAgent | None = None
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
        msg = json.dumps({
            "type": msg_type,
            "session_id": self._session_id,
            "timestamp": time.time(),
            **payload,
        })
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

        # Active task agent gets all messages
        if self._task_agent and self._task_agent.is_active:
            self._current_intent = Intent.TASK_MANAGEMENT
            self._current_response_type = "task_response"
            return await self._route_to_task_agent(text)

        # Classify intent
        try:
            classification = await classify_intent([("user", text)])
        except Exception as e:
            logger.error(f"Intent classification failed: {e}", exc_info=True)
            self._current_intent = None
            self._current_response_type = "error"
            return Err(f"Configuration error: {e}")

        logger.debug(f"Intent: {classification.intent} (confidence: {classification.confidence:.2f})")

        # Store intent for response metadata
        self._current_intent = classification.intent
        self._current_response_type = "llm_response"

        # Route task management to task agent
        if classification.intent == Intent.TASK_MANAGEMENT:
            self._current_response_type = "task_response"
            return await self._route_to_task_agent(text)

        # Default LLM flow
        return Ok(None)

    async def _route_to_task_agent(self, text: str) -> Result[str]:
        """Route message to task agent."""
        if not self._task_agent:
            self._task_agent = TaskAgent(
                session_id=self._session_id,
                provider=self._settings.task_agent_provider,
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
            case Ok(response):
                await self._speak_and_stop(response)

    async def _get_response(self, result: Result, user_input: str) -> AsyncIterable[str]:
        """Get response chunks - pre-made or generated."""
        match result:
            case Err(error):
                yield error
            case Ok(None):
                async for chunk in self._generate_llm(user_input):
                    yield chunk
            case Ok(response):
                yield response

    async def _generate_llm(self, user_input: str) -> AsyncIterable[str]:
        """Generate response chunks from LLM."""
        model = get_llm_by_model_id(self._settings.llm_model)
        if not model:
            logger.error(f"Unknown model: {self._settings.llm_model}")
            yield f"Error: Unknown model '{self._settings.llm_model}'. Check configuration."
            return

        llm_client = ChatOpenAI(
            base_url=model.base_url,
            api_key=model.api_key,
            model=model.model_id,
            streaming=True,
        )

        async for chunk in llm_client.astream([("user", user_input)]):
            if chunk.content:
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


class TranscribeAgent(Agent):
    """Transcribe mode: STT only, emit transcripts without LLM response"""

    def __init__(self, settings: AgentSettings):
        super().__init__(
            instructions="",
            stt=create_stt(settings.stt_provider),
        )

    async def on_user_turn_completed(
        self, turn_ctx: llm.ChatContext, new_message: llm.ChatMessage
    ) -> None:
        transcript = new_message.text_content
        logger.info(f"Transcribed: {transcript}")
        raise StopResponse()


def get_settings_from_metadata(ctx: JobContext) -> AgentSettings:
    """Extract settings from participant or room metadata."""
    merged: dict = {}

    for participant in ctx.room.remote_participants.values():
        if participant.metadata:
            try:
                merged.update(json.loads(participant.metadata))
                logger.info(f"Settings from participant {participant.identity}: {merged}")
                break
            except json.JSONDecodeError:
                pass

    if ctx.room.metadata:
        try:
            merged.update(json.loads(ctx.room.metadata))
            logger.info(f"Settings from room metadata: {merged}")
        except json.JSONDecodeError:
            pass

    return AgentSettings.from_dict(merged)


@dataclass
class SessionState:
    """Mutable state for an agent session."""

    settings: AgentSettings = field(default_factory=AgentSettings)
    agent: "ChatAgent | None" = None
    session: AgentSession | None = None


server = AgentServer()


def prewarm(proc: JobProcess):
    """Prewarm VAD model for faster startup."""
    proc.userdata["vad"] = silero.VAD.load()


server.setup_fnc = prewarm




@server.rtc_session()
async def entrypoint(ctx: JobContext):
    logger.info(f"Starting voice agent for room: {ctx.room.name}")
    await ctx.connect(auto_subscribe=AutoSubscribe.AUDIO_ONLY)

    initial_settings = get_settings_from_metadata(ctx)
    logger.info(f"Initial settings: {initial_settings}")

    # Session state - single object holds all mutable state
    state = SessionState(
        settings=initial_settings,
        session=AgentSession(
            vad=ctx.proc.userdata["vad"],
            turn_detection=MultilingualModel(),
            preemptive_generation=True,
        ),
    )

    def create_agent(settings: AgentSettings) -> Agent:
        """Create agent based on current settings."""
        if settings.agent_mode == "chat":
            agent = ChatAgent(settings)
            agent.set_room(ctx.room)
            state.agent = agent
            return agent
        else:
            state.agent = None
            return TranscribeAgent(settings)

    # Register text input handler (works without voice session)
    def on_text_input(reader: rtc.TextStreamReader, participant_id: str):
        """Handle text messages from client."""
        async def _handle():
            try:
                text = await reader.read_all()
                if not text.strip():
                    return

                logger.info(f"Processing text input: {text[:50]}...")

                # Create agent if none exists (text before voice)
                if not state.agent:
                    state.agent = ChatAgent(state.settings)
                    state.agent.set_room(ctx.room)
                    logger.info("Created ChatAgent for text input")

                agent = state.agent
                result = await agent._process_input(text)
                response = agent._get_response(result, text)
                await agent._send(response)

                logger.info("Text response complete")
            except Exception as e:
                logger.error(f"Text input failed: {e}", exc_info=True)

        asyncio.create_task(_handle())

    ctx.room.register_text_stream_handler(TOPIC_TEXT_INPUT, on_text_input)
    logger.info("Text input handler registered")

    def on_stt_metrics(m: metrics.STTMetrics):
        """Log STT metrics including provider and audio duration."""
        logger.info(
            f"STT call: provider={state.settings.stt_provider} "
            f"audio_duration={m.audio_duration:.2f}s "
            f"latency={m.duration:.2f}s streamed={m.streamed}"
        )

    def on_user_state_changed(ev: UserStateChangedEvent):
        """Reset inactivity timer when user completes a turn."""
        logger.debug(f"User state changed: {ev.old_state} -> {ev.new_state}")
        if not state.agent or not isinstance(state.agent, ChatAgent):
            return

        # Reset timer when user finishes speaking (turn completed)
        if ev.old_state == "speaking" and ev.new_state != "speaking":
            state.agent.on_turn_completed()

    async def _start_session():
        """Start agent session when user enables mic."""
        agent = create_agent(state.settings)
        await state.session.start(
            agent=agent,
            room=ctx.room,
            room_options=room_io.RoomOptions(
                text_output=True,
                audio_output=(state.settings.agent_mode == "chat"),
            ),
        )
        state.session.on("user_state_changed", on_user_state_changed)
        if state.session.stt:
            state.session.stt.on("metrics_collected", on_stt_metrics)

        # Start session timer and notify frontend
        if agent and isinstance(agent, ChatAgent):
            agent.start_session_timer()
            await agent._send_session_notification(NotificationType.SESSION_READY)

    async def _stop_session():
        """Stop agent session when user disables mic."""
        if state.agent and isinstance(state.agent, ChatAgent):
            state.agent.stop_session_timer()

        await state.session.aclose()
        # Recreate session for next connection
        state.session = AgentSession(
            vad=ctx.proc.userdata["vad"],
            turn_detection=MultilingualModel(),
            preemptive_generation=True,
        )
        state.agent = None

    async def _apply_settings(new_settings: AgentSettings):
        """Apply new settings, restarting session if needed."""
        old = state.settings

        if new_settings == old:
            return

        logger.info(f"Settings changed: {old} -> {new_settings}")
        state.settings = new_settings

        await state.session.aclose()
        state.session = AgentSession(
            vad=ctx.proc.userdata["vad"],
            turn_detection=MultilingualModel(),
            preemptive_generation=True,
        )

        agent = create_agent(new_settings)
        await state.session.start(
            agent=agent,
            room=ctx.room,
            room_options=room_io.RoomOptions(
                text_output=True,
                audio_output=(new_settings.agent_mode == "chat"),
            ),
        )
        state.session.on("user_state_changed", on_user_state_changed)
        if state.session.stt:
            state.session.stt.on("metrics_collected", on_stt_metrics)

    @ctx.room.on("track_subscribed")
    def on_track_subscribed(
        track: rtc.Track,
        publication: rtc.TrackPublication,
        participant: rtc.RemoteParticipant,
    ):
        """Start agent session when user's audio track is subscribed."""
        if track.kind == rtc.TrackKind.KIND_AUDIO:
            logger.info(f"Audio track subscribed from {participant.identity}")
            asyncio.create_task(_start_session())

    @ctx.room.on("track_unsubscribed")
    def on_track_unsubscribed(
        track: rtc.Track,
        publication: rtc.TrackPublication,
        participant: rtc.RemoteParticipant,
    ):
        """Stop agent session when user's audio track is unsubscribed."""
        if track.kind == rtc.TrackKind.KIND_AUDIO:
            logger.info(f"Audio track unsubscribed from {participant.identity}")
            asyncio.create_task(_stop_session())

    @ctx.room.on("participant_metadata_changed")
    def on_metadata_changed(participant, prev_metadata):
        if participant.metadata:
            try:
                meta = json.loads(participant.metadata)
                new_settings = AgentSettings.from_dict(meta)
                if new_settings != state.settings:
                    asyncio.create_task(_apply_settings(new_settings))
            except json.JSONDecodeError:
                pass

    # Session will be started when audio track is subscribed (user enables mic)
    logger.info("Agent ready, waiting for audio track subscription")


if __name__ == "__main__":
    cli.run_app(server)
