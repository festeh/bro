import asyncio
import json
import logging
import os
import time
import uuid
from collections.abc import AsyncIterable
from typing import Literal

from dotenv import load_dotenv
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

from constants import ATTR_SEGMENT_ID, ATTR_TRANSCRIPTION_FINAL, TOPIC_LLM_STREAM, TOPIC_VAD_STATUS

load_dotenv()

# Turn duration limits
MAX_TURN_DURATION = 60.0  # seconds
TURN_WARNING_THRESHOLD = 55.0  # seconds

NotificationType = Literal["turn_warning", "turn_terminated"]

logger = logging.getLogger("voice-agent")

# LLM model mapping (Flutter enum name -> Chutes model ID)
LLM_MODELS = {
    "glm47": "zai-org/GLM-4.7-TEE",
    "mimoV2": "XiaomiMiMo/MiMo-V2-Flash",
    "minimax": "MiniMaxAI/MiniMax-M2.1-TEE",
    "kimiK2": "moonshotai/Kimi-K2-Thinking-TEE",
    "deepseekV31": "deepseek-ai/DeepSeek-V3.1-Terminus-TEE",
}

DEFAULT_LLM_MODEL = "deepseekV31"
DEFAULT_STT_PROVIDER = "deepgram"
DEFAULT_TTS_ENABLED = True


def create_stt(provider: str):
    """Create STT instance based on provider name."""
    if provider == "elevenlabs":
        return elevenlabs.STT()
    # Default to deepgram
    return deepgram.STT(model="nova-3")


def create_llm(model_key: str):
    """Create LLM instance based on model key."""
    model_id = LLM_MODELS.get(model_key, LLM_MODELS[DEFAULT_LLM_MODEL])
    return openai.LLM(
        model=model_id,
        base_url="https://llm.chutes.ai/v1",
        api_key=os.environ.get("CHUTES_API_KEY", ""),
    )


class ChatAgent(Agent):
    """Chat mode: STT → LLM → TTS with auto turn detection and immediate text streaming"""

    def __init__(
        self,
        stt_provider: str = DEFAULT_STT_PROVIDER,
        llm_model: str = DEFAULT_LLM_MODEL,
        tts_enabled: bool = DEFAULT_TTS_ENABLED,
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
        # Turn duration tracking
        self._turn_id: str | None = None
        self._turn_start_time: float | None = None
        self._turn_warning_sent: bool = False
        self._turn_monitor_task: asyncio.Task | None = None

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

    async def _send_turn_notification(self, msg_type: NotificationType, **payload) -> None:
        """Send turn notification to frontend via LiveKit data topic."""
        if not self._room:
            return
        msg = json.dumps({
            "type": msg_type,
            "turn_id": self._turn_id,
            "timestamp": time.time(),
            **payload,
        })
        try:
            writer = await self._room.local_participant.stream_text(topic=TOPIC_VAD_STATUS)
            await writer.write(msg)
            await writer.aclose()
            logger.debug(f"Turn notification sent: {msg_type} turn={self._turn_id}")
        except Exception as e:
            logger.warning(f"Failed to send turn notification: {e}")

    def on_speech_start(self) -> None:
        """Called when user starts speaking."""
        self._turn_id = f"turn_{uuid.uuid4().hex[:8]}"
        self._turn_warning_sent = False
        self._turn_start_time = time.time()
        self._turn_monitor_task = asyncio.create_task(self._monitor_turn_duration())
        logger.debug(f"Speech started: turn={self._turn_id}")

    def on_speech_end(self) -> None:
        """Called when user stops speaking."""
        if self._turn_monitor_task:
            self._turn_monitor_task.cancel()
            self._turn_monitor_task = None
        self._turn_warning_sent = False
        logger.debug(f"Speech ended: turn={self._turn_id}")

    async def _monitor_turn_duration(self) -> None:
        """Background task to monitor turn duration and enforce limits."""
        try:
            while True:
                await asyncio.sleep(0.5)
                if not self._turn_start_time:
                    break

                elapsed = time.time() - self._turn_start_time

                # Send warning at 55s
                if elapsed >= TURN_WARNING_THRESHOLD and not self._turn_warning_sent:
                    remaining = int(MAX_TURN_DURATION - elapsed)
                    await self._send_turn_notification("turn_warning", remaining_seconds=remaining)
                    self._turn_warning_sent = True
                    logger.info(f"Turn warning: {remaining}s remaining turn={self._turn_id}")

                # Terminate at 60s
                if elapsed >= MAX_TURN_DURATION:
                    await self._send_turn_notification(
                        "turn_terminated",
                        reason="max_duration",
                        final_duration=elapsed,
                    )
                    logger.info(f"Turn terminated: duration={elapsed:.2f}s turn={self._turn_id}")
                    break
        except asyncio.CancelledError:
            pass


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


server = AgentServer()


def prewarm(proc: JobProcess):
    """Prewarm VAD model for faster startup."""
    proc.userdata["vad"] = silero.VAD.load()


server.setup_fnc = prewarm


@server.rtc_session()
async def entrypoint(ctx: JobContext):
    logger.info(f"Starting voice agent for room: {ctx.room.name}")
    await ctx.connect(auto_subscribe=AutoSubscribe.AUDIO_ONLY)

    settings = get_settings_from_metadata(ctx)
    logger.info(f"Initial settings: {settings}")

    session = AgentSession(
        vad=ctx.proc.userdata["vad"],
        turn_detection=MultilingualModel(),
        preemptive_generation=True,
    )

    current_settings = [settings.copy()]
    current_agent: list[ChatAgent | None] = [None]

    def on_stt_metrics(m: metrics.STTMetrics):
        """Log STT metrics including provider and audio duration."""
        provider = current_settings[0]["stt_provider"]
        logger.info(
            f"STT call: provider={provider} audio_duration={m.audio_duration:.2f}s "
            f"latency={m.duration:.2f}s streamed={m.streamed}"
        )

    def on_user_state_changed(ev: UserStateChangedEvent):
        """Track turn timing for duration limits."""
        logger.debug(f"User state changed: {ev.old_state} -> {ev.new_state}")
        agent = current_agent[0]
        if not agent or not isinstance(agent, ChatAgent):
            return

        if ev.new_state == "speaking" and ev.old_state != "speaking":
            agent.on_speech_start()
        elif ev.old_state == "speaking" and ev.new_state != "speaking":
            agent.on_speech_end()

    def create_agent(s: dict) -> Agent:
        """Create agent based on current settings."""
        if s["agent_mode"] == "chat":
            agent = ChatAgent(
                stt_provider=s["stt_provider"],
                llm_model=s["llm_model"],
                tts_enabled=s["tts_enabled"],
            )
            agent.set_room(ctx.room)
            current_agent[0] = agent
            return agent
        else:
            current_agent[0] = None
            return TranscribeAgent(stt_provider=s["stt_provider"])

    async def _apply_settings(new_settings: dict):
        nonlocal session
        old = current_settings[0]

        mode_changed = new_settings["agent_mode"] != old["agent_mode"]
        stt_changed = new_settings["stt_provider"] != old["stt_provider"]
        llm_changed = new_settings["llm_model"] != old["llm_model"]
        tts_changed = new_settings["tts_enabled"] != old["tts_enabled"]

        if not (mode_changed or stt_changed or llm_changed or tts_changed):
            return

        logger.info(f"Settings changed: {old} -> {new_settings}")
        current_settings[0] = new_settings.copy()

        await session.aclose()
        session = AgentSession(
            vad=ctx.proc.userdata["vad"],
            turn_detection=MultilingualModel(),
            preemptive_generation=True,
        )

        agent = create_agent(new_settings)
        await session.start(
            agent=agent,
            room=ctx.room,
            room_options=room_io.RoomOptions(
                text_output=True,
                audio_output=(new_settings["agent_mode"] == "chat"),
            ),
        )
        session.on("user_state_changed", on_user_state_changed)
        if session.stt:
            session.stt.on("metrics_collected", on_stt_metrics)

    @ctx.room.on("participant_metadata_changed")
    def on_metadata_changed(participant, prev_metadata):
        if participant.metadata:
            try:
                meta = json.loads(participant.metadata)
                new_settings = current_settings[0].copy()
                changed = False
                for key in new_settings:
                    if key in meta and meta[key] != new_settings[key]:
                        new_settings[key] = meta[key]
                        changed = True
                if changed:
                    asyncio.create_task(_apply_settings(new_settings))
            except json.JSONDecodeError:
                pass

    agent = create_agent(settings)
    await session.start(
        agent=agent,
        room=ctx.room,
        room_options=room_io.RoomOptions(
            text_output=True,
            audio_output=(settings["agent_mode"] == "chat"),
        ),
    )
    session.on("user_state_changed", on_user_state_changed)
    if session.stt:
        session.stt.on("metrics_collected", on_stt_metrics)


if __name__ == "__main__":
    cli.run_app(server)
