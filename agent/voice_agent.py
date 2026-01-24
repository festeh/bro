import asyncio
import json
import logging
import time
import uuid
from collections.abc import AsyncIterable
from dataclasses import dataclass, field
from enum import StrEnum

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

# Session inactivity timeout
SESSION_TIMEOUT = 60.0  # seconds without completed turn
SESSION_WARNING_THRESHOLD = 55.0  # seconds


class NotificationType(StrEnum):
    """Session notification types."""

    SESSION_WARNING = "session_warning"
    SESSION_TIMEOUT = "session_timeout"
    SESSION_READY = "session_ready"

logger = logging.getLogger("voice-agent")

# Legacy mapping for old Flutter enum names -> model_id (for backward compatibility)
_LEGACY_MODEL_KEYS = {
    "glm47": "zai-org/GLM-4.7-TEE",
    "mimoV2": "XiaomiMiMo/MiMo-V2-Flash",
    "minimax": "MiniMaxAI/MiniMax-M2.1-TEE",
    "kimiK2": "moonshotai/Kimi-K2-Thinking-TEE",
    "deepseekV31": "deepseek-ai/DeepSeek-V3.1-Terminus-TEE",
}

DEFAULT_LLM_MODEL = get_default_llm().model_id
DEFAULT_STT_PROVIDER = "deepgram"
DEFAULT_TTS_ENABLED = True
DEFAULT_TASK_AGENT_PROVIDER = "groq"


def create_stt(provider: str):
    """Create STT instance based on provider name."""
    if provider == "elevenlabs":
        return elevenlabs.STT()
    # Default to deepgram
    return deepgram.STT(model="nova-3")


def create_llm(model_key: str):
    """Create LLM instance based on model key or model_id."""
    # Try legacy mapping first (for old Flutter enum names)
    model_id = _LEGACY_MODEL_KEYS.get(model_key)

    if model_id:
        # Found in legacy mapping, look up full model config
        model = get_llm_by_model_id(model_id)
    else:
        # Assume it's a model_id directly
        model = get_llm_by_model_id(model_key)

    if not model:
        # Fallback to default
        logger.warning(f"Unknown model key: {model_key}, using default")
        model = get_default_llm()

    return openai.LLM(
        model=model.model_id,
        base_url=model.base_url,
        api_key=model.api_key,
    )


class ChatAgent(Agent):
    """Chat mode: STT → LLM → TTS with auto turn detection and immediate text streaming"""

    def __init__(
        self,
        stt_provider: str = DEFAULT_STT_PROVIDER,
        llm_model: str = DEFAULT_LLM_MODEL,
        tts_enabled: bool = DEFAULT_TTS_ENABLED,
        task_agent_provider: str = DEFAULT_TASK_AGENT_PROVIDER,
    ):
        super().__init__(
            instructions="You are a helpful voice assistant. Keep responses concise and conversational.",
            stt=create_stt(stt_provider),
            llm=create_llm(llm_model),
            tts=elevenlabs.TTS() if tts_enabled else None,
        )
        self._room: rtc.Room | None = None
        self._immediate_writer: rtc.TextStreamWriter | None = None
        self._segment_id: str = ""
        # Session inactivity timeout
        self._session_id: str = ""
        self._last_activity_time: float | None = None
        self._session_warning_sent: bool = False
        self._session_monitor_task: asyncio.Task | None = None
        # Task agent for task management sub-flow
        self._task_agent: TaskAgent | None = None
        self._task_agent_provider = task_agent_provider

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
            self._immediate_writer = await self._room.local_participant.stream_text(
                topic=TOPIC_LLM_STREAM,
                attributes={
                    ATTR_SEGMENT_ID: self._segment_id,
                    ATTR_TRANSCRIPTION_FINAL: "false",
                },
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

    async def on_user_turn_completed(
        self, turn_ctx: llm.ChatContext, new_message: llm.ChatMessage
    ) -> None:
        """Handle user message - route to task agent if needed."""
        user_text = new_message.text_content or ""

        # If task agent is active, route all messages to it
        if self._task_agent and self._task_agent.is_active:
            response = await self._task_agent.process_message(user_text)
            logger.info(f"Task agent response: {response.text[:100]}...")

            if response.should_exit:
                logger.info(f"Task agent exiting: {response.exit_reason}")
                self._task_agent = None

            # Send response and stop default LLM flow
            await self._speak_and_stop(response.text)
            return

        # Classify intent using LLM
        classification = await classify_intent([("user", user_text)])
        logger.debug(
            f"Intent classified: {classification.intent} "
            f"(confidence: {classification.confidence:.2f})"
        )

        # Route task_management intent to task agent
        if classification.intent == Intent.TASK_MANAGEMENT:
            logger.info(f"Task intent detected: {user_text[:50]}...")

            # Create task agent if needed
            if not self._task_agent:
                self._task_agent = TaskAgent(
                    session_id=self._session_id,
                    provider=self._task_agent_provider,
                )

            response = await self._task_agent.process_message(user_text)
            logger.info(f"Task agent response: {response.text[:100]}...")

            # Send response and stop default LLM flow
            await self._speak_and_stop(response.text)
            return

        # Not a task message - let default LLM flow continue
        # (don't raise StopResponse, let Agent handle normally)

    async def _speak_and_stop(self, text: str) -> None:
        """Send text to frontend and stop default response flow."""
        # Stream text immediately to frontend
        if self._room:
            self._segment_id = f"TASK_{uuid.uuid4().hex[:8]}"
            writer = await self._room.local_participant.stream_text(
                topic=TOPIC_LLM_STREAM,
                attributes={
                    ATTR_SEGMENT_ID: self._segment_id,
                    ATTR_TRANSCRIPTION_FINAL: "true",
                },
            )
            await writer.write(text)
            await writer.aclose()

        # TODO: Integrate TTS for task agent responses
        # For now, text is sent to frontend for display

        raise StopResponse()


class TranscribeAgent(Agent):
    """Transcribe mode: STT only, emit transcripts without LLM response"""

    def __init__(self, stt_provider: str = DEFAULT_STT_PROVIDER):
        super().__init__(
            instructions="",
            stt=create_stt(stt_provider),
        )

    async def on_user_turn_completed(
        self, turn_ctx: llm.ChatContext, new_message: llm.ChatMessage
    ) -> None:
        transcript = new_message.text_content
        logger.info(f"Transcribed: {transcript}")
        raise StopResponse()


def get_settings_from_metadata(ctx: JobContext) -> dict:
    """Extract settings from participant or room metadata."""
    settings = {
        "agent_mode": "chat",
        "stt_provider": DEFAULT_STT_PROVIDER,
        "llm_model": DEFAULT_LLM_MODEL,
        "tts_enabled": DEFAULT_TTS_ENABLED,
        "task_agent_provider": DEFAULT_TASK_AGENT_PROVIDER,
    }

    for participant in ctx.room.remote_participants.values():
        if participant.metadata:
            try:
                meta = json.loads(participant.metadata)
                for key in settings:
                    if key in meta:
                        settings[key] = meta[key]
                logger.info(f"Settings from participant {participant.identity}: {settings}")
                break
            except json.JSONDecodeError:
                pass

    if ctx.room.metadata:
        try:
            meta = json.loads(ctx.room.metadata)
            for key in settings:
                if key in meta:
                    settings[key] = meta[key]
            logger.info(f"Settings from room metadata: {settings}")
        except json.JSONDecodeError:
            pass

    return settings


@dataclass
class SessionState:
    """Mutable state for an agent session."""

    settings: dict = field(default_factory=dict)
    agent: "ChatAgent | None" = None
    session: AgentSession | None = None

    def update_settings(self, new_settings: dict) -> bool:
        """Update settings and return True if changed."""
        if new_settings == self.settings:
            return False
        self.settings = new_settings.copy()
        return True


server = AgentServer()


def prewarm(proc: JobProcess):
    """Prewarm VAD model for faster startup."""
    proc.userdata["vad"] = silero.VAD.load()


server.setup_fnc = prewarm


async def process_text_input(
    room: rtc.Room,
    text: str,
    llm_model: str,
    tts_enabled: bool,
) -> None:
    """Process text input from client, respond via LLM and optionally TTS."""
    segment_id = f"TEXT_{uuid.uuid4().hex[:8]}"
    logger.info(f"Processing text input: {text[:50]}... (tts={tts_enabled})")

    # Get model config and create langchain LLM
    model = get_llm_by_model_id(llm_model)
    if not model:
        model = get_default_llm()
    llm = ChatOpenAI(
        base_url=model.base_url,
        api_key=model.api_key,
        model=model.model_id,
        streaming=True,
    )
    messages = [("user", text)]

    # Stream response to lk.llm_stream
    full_response = ""
    writer = await room.local_participant.stream_text(
        topic=TOPIC_LLM_STREAM,
        attributes={
            ATTR_SEGMENT_ID: segment_id,
            ATTR_TRANSCRIPTION_FINAL: "false",
        },
    )

    try:
        async for chunk in llm.astream(messages):
            if chunk.content:
                full_response += chunk.content
                await writer.write(chunk.content)
    finally:
        await writer.aclose()

    logger.info(f"Text response complete: {len(full_response)} chars")

    # TTS if enabled
    if tts_enabled and full_response:
        try:
            tts = elevenlabs.TTS()
            audio_stream = tts.synthesize(full_response)
            # Publish audio to room
            source = rtc.AudioSource(sample_rate=24000, num_channels=1)
            track = rtc.LocalAudioTrack.create_audio_track("tts_response", source)
            await room.local_participant.publish_track(track)

            async for frame in audio_stream:
                await source.capture_frame(frame.frame)

            await room.local_participant.unpublish_track(track.sid)
            logger.info("TTS playback complete")
        except Exception as e:
            logger.warning(f"TTS failed: {e}")


@server.rtc_session()
async def entrypoint(ctx: JobContext):
    logger.info(f"Starting voice agent for room: {ctx.room.name}")
    await ctx.connect(auto_subscribe=AutoSubscribe.AUDIO_ONLY)

    initial_settings = get_settings_from_metadata(ctx)
    logger.info(f"Initial settings: {initial_settings}")

    # Session state - single object holds all mutable state
    state = SessionState(
        settings=initial_settings.copy(),
        session=AgentSession(
            vad=ctx.proc.userdata["vad"],
            turn_detection=MultilingualModel(),
            preemptive_generation=True,
        ),
    )

    def create_agent(s: dict) -> Agent:
        """Create agent based on current settings."""
        if s["agent_mode"] == "chat":
            agent = ChatAgent(
                stt_provider=s["stt_provider"],
                llm_model=s["llm_model"],
                tts_enabled=s["tts_enabled"],
                task_agent_provider=s["task_agent_provider"],
            )
            agent.set_room(ctx.room)
            state.agent = agent
            return agent
        else:
            state.agent = None
            return TranscribeAgent(stt_provider=s["stt_provider"])

    # Register text input handler (works without voice session)
    def on_text_input(reader: rtc.TextStreamReader, participant_id: str):
        """Handle text messages from client."""
        async def _handle():
            try:
                text = await reader.read_all()
                if not text.strip():
                    return
                await process_text_input(
                    room=ctx.room,
                    text=text,
                    llm_model=state.settings["llm_model"],
                    tts_enabled=state.settings["tts_enabled"],
                )
            except Exception as e:
                logger.error(f"Text input processing failed: {e}")

        asyncio.create_task(_handle())

    ctx.room.register_text_stream_handler(TOPIC_TEXT_INPUT, on_text_input)
    logger.info("Text input handler registered")

    def on_stt_metrics(m: metrics.STTMetrics):
        """Log STT metrics including provider and audio duration."""
        logger.info(
            f"STT call: provider={state.settings['stt_provider']} "
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
                audio_output=(state.settings["agent_mode"] == "chat"),
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

    async def _apply_settings(new_settings: dict):
        """Apply new settings, restarting session if needed."""
        old = state.settings

        mode_changed = new_settings["agent_mode"] != old["agent_mode"]
        stt_changed = new_settings["stt_provider"] != old["stt_provider"]
        llm_changed = new_settings["llm_model"] != old["llm_model"]
        tts_changed = new_settings["tts_enabled"] != old["tts_enabled"]
        task_provider_changed = new_settings["task_agent_provider"] != old["task_agent_provider"]

        if not (mode_changed or stt_changed or llm_changed or tts_changed or task_provider_changed):
            return

        logger.info(f"Settings changed: {old} -> {new_settings}")
        state.settings = new_settings.copy()

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
                audio_output=(new_settings["agent_mode"] == "chat"),
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
                new_settings = state.settings.copy()
                changed = False
                for key in new_settings:
                    if key in meta and meta[key] != new_settings[key]:
                        new_settings[key] = meta[key]
                        changed = True
                if changed:
                    asyncio.create_task(_apply_settings(new_settings))
            except json.JSONDecodeError:
                pass

    # Session will be started when audio track is subscribed (user enables mic)
    logger.info("Agent ready, waiting for audio track subscription")


if __name__ == "__main__":
    cli.run_app(server)
