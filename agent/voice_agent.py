import asyncio
import json
import logging
import os
import time
import uuid
from dataclasses import dataclass
from typing import AsyncIterable, Literal

import numpy as np
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
from livekit.agents.voice import UserStateChangedEvent
from livekit.agents.voice import ModelSettings
from livekit.plugins import deepgram, elevenlabs, openai, silero
from livekit.plugins.turn_detector.multilingual import MultilingualModel

from constants import TOPIC_LLM_STREAM, TOPIC_VAD_STATUS, ATTR_SEGMENT_ID, ATTR_TRANSCRIPTION_FINAL

load_dotenv()

# Type aliases
ASRProvider = Literal["deepgram", "elevenlabs"]
NotificationType = Literal["turn_warning", "turn_terminated", "asr_connection_failed"]


@dataclass
class VADGatingConfig:
    """Runtime configuration for VAD gating layer.

    Note: connection_buffer_max is defined for future ASR connection failure
    buffering (T024-T025). Implementation requires STT connection lifecycle
    hooks which are internal to livekit-agents framework.
    """
    max_turn_duration: float = 60.0
    warning_threshold: float = 55.0
    grace_period: float = 2.0
    min_silence_duration: float = 0.3
    connection_buffer_max: float = 5.0
    notification_topic: str = TOPIC_VAD_STATUS


@dataclass
class VADGatingState:
    """Minimal state - most fields reused from AudioRecognition."""
    session_id: str
    turn_id: str | None = None
    warning_sent: bool = False
    asr_provider: ASRProvider = "deepgram"


@dataclass
class VADGatingMetrics:
    """Accumulated metrics for a voice session."""
    session_id: str
    asr_provider: ASRProvider
    total_audio_duration: float = 0.0
    transmitted_duration: float = 0.0
    filtered_duration: float = 0.0
    speech_segments: int = 0
    turns_completed: int = 0
    turns_terminated: int = 0
    session_start_time: float = 0.0

logger = logging.getLogger("voice-agent")


def calculate_audio_level(frame: rtc.AudioFrame) -> tuple[float, float]:
    """Calculate RMS and peak audio levels from an AudioFrame.

    Returns:
        Tuple of (rms_db, peak_db) in dB relative to full scale.
    """
    data = np.frombuffer(frame.data, dtype=np.int16)
    if len(data) == 0:
        return -100.0, -100.0

    # Calculate RMS
    rms = np.sqrt(np.mean(data.astype(np.float32) ** 2))
    peak = np.max(np.abs(data))

    # Convert to dB (relative to 16-bit full scale)
    max_int16 = 32767
    rms_db = 20 * np.log10(max(rms / max_int16, 1e-10))
    peak_db = 20 * np.log10(max(peak / max_int16, 1e-10))

    return float(rms_db), float(peak_db)

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
        # VAD gating state
        self._vad_config = VADGatingConfig()
        self._vad_state = VADGatingState(
            session_id=uuid.uuid4().hex,
            asr_provider=stt_provider if stt_provider in ("deepgram", "elevenlabs") else "deepgram",
        )
        self._vad_metrics = VADGatingMetrics(
            session_id=self._vad_state.session_id,
            asr_provider=self._vad_state.asr_provider,
            session_start_time=time.time(),
        )
        self._turn_start_time: float | None = None
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

    async def _send_vad_notification(self, msg_type: NotificationType, **payload) -> None:
        """Send VAD notification to frontend via LiveKit data topic."""
        if not self._room:
            return
        msg = json.dumps({
            "type": msg_type,
            "turn_id": self._vad_state.turn_id,
            "timestamp": time.time(),
            **payload,
        })
        try:
            writer = await self._room.local_participant.stream_text(
                topic=self._vad_config.notification_topic
            )
            await writer.write(msg)
            await writer.aclose()
            logger.debug(f"VAD notification sent: {msg_type} turn={self._vad_state.turn_id}")
        except Exception as e:
            logger.warning(f"Failed to send VAD notification: {e}")

    def on_speech_start(self) -> None:
        """Called when user starts speaking. Generates turn_id and resets state."""
        self._vad_state.turn_id = f"turn_{uuid.uuid4().hex[:8]}"
        self._vad_state.warning_sent = False
        self._turn_start_time = time.time()
        self._vad_metrics.speech_segments += 1
        self._turn_monitor_task = asyncio.create_task(self._monitor_turn_duration())
        logger.debug(f"Speech started: turn={self._vad_state.turn_id}")

    def on_speech_end(self, speech_duration: float) -> None:
        """Called when user stops speaking. Updates metrics."""
        if hasattr(self, "_turn_monitor_task") and self._turn_monitor_task:
            self._turn_monitor_task.cancel()
            self._turn_monitor_task = None
        self._vad_metrics.transmitted_duration += speech_duration
        self._vad_metrics.turns_completed += 1
        self._vad_state.warning_sent = False
        logger.debug(f"Speech ended: turn={self._vad_state.turn_id} duration={speech_duration:.2f}s")

    async def _monitor_turn_duration(self) -> None:
        """Background task to monitor turn duration and enforce limits."""
        try:
            while True:
                await asyncio.sleep(0.5)  # Check every 500ms
                if not self._turn_start_time:
                    break

                elapsed = time.time() - self._turn_start_time

                # Send warning at threshold (55s by default)
                if elapsed >= self._vad_config.warning_threshold and not self._vad_state.warning_sent:
                    remaining = int(self._vad_config.max_turn_duration - elapsed)
                    await self._send_vad_notification(
                        "turn_warning",
                        remaining_seconds=remaining,
                    )
                    self._vad_state.warning_sent = True
                    logger.info(f"Turn warning sent: {remaining}s remaining turn={self._vad_state.turn_id}")

                # Terminate at max duration (60s by default)
                if elapsed >= self._vad_config.max_turn_duration:
                    await self._send_vad_notification(
                        "turn_terminated",
                        reason="max_duration",
                        final_duration=elapsed,
                    )
                    self._vad_metrics.turns_terminated += 1
                    logger.info(f"Turn terminated: duration={elapsed:.2f}s turn={self._vad_state.turn_id}")
                    break
        except asyncio.CancelledError:
            pass

    def log_session_metrics(self) -> None:
        """Log VAD gating metrics at session end."""
        session_duration = time.time() - self._vad_metrics.session_start_time
        self._vad_metrics.total_audio_duration = session_duration
        self._vad_metrics.filtered_duration = (
            self._vad_metrics.total_audio_duration - self._vad_metrics.transmitted_duration
        )

        # Calculate filtering ratio
        filtering_ratio = 0.0
        if self._vad_metrics.total_audio_duration > 0:
            filtering_ratio = self._vad_metrics.filtered_duration / self._vad_metrics.total_audio_duration

        metrics_dict = {
            "session_id": self._vad_metrics.session_id,
            "asr_provider": self._vad_metrics.asr_provider,
            "total_audio_duration": round(self._vad_metrics.total_audio_duration, 2),
            "transmitted_duration": round(self._vad_metrics.transmitted_duration, 2),
            "filtered_duration": round(self._vad_metrics.filtered_duration, 2),
            "filtering_ratio": round(filtering_ratio, 2),
            "speech_segments": self._vad_metrics.speech_segments,
            "turns_completed": self._vad_metrics.turns_completed,
            "turns_terminated": self._vad_metrics.turns_terminated,
        }

        logger.info(f"VAD gating metrics: {json.dumps(metrics_dict)}")


class TranscribeAgent(Agent):
    """Transcribe mode: STT only, emit transcripts without LLM response"""

    def __init__(self, stt_provider: str = DEFAULT_STT_PROVIDER):
        super().__init__(
            instructions="",
            stt=create_stt(stt_provider),
        )

    async def on_user_turn_completed(
        self, chat_ctx: llm.ChatContext, new_message: llm.ChatMessage
    ):
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
    # Testing with default threshold to investigate detection issue
    proc.userdata["vad"] = silero.VAD.load(activation_threshold=0.5)


server.setup_fnc = prewarm


@server.rtc_session()
async def entrypoint(ctx: JobContext):
    logger.info(f"Starting voice agent for room: {ctx.room.name}")
    await ctx.connect(auto_subscribe=AutoSubscribe.AUDIO_ONLY)

    settings = get_settings_from_metadata(ctx)
    logger.info(f"Initial settings: {settings}")

    vad_obj = ctx.proc.userdata["vad"]
    logger.info(f"VAD object from prewarm: {vad_obj}, type: {type(vad_obj)}")

    session = AgentSession(
        vad=vad_obj,
        turn_detection=MultilingualModel(),
        preemptive_generation=True,
    )
    logger.info(f"Session created with VAD: {session.vad}")

    current_settings = [settings.copy()]
    current_agent: list[ChatAgent | None] = [None]
    user_speech_start_time: list[float | None] = [None]

    def on_stt_metrics(m: metrics.STTMetrics):
        """Log STT metrics including provider and audio duration."""
        provider = current_settings[0]["stt_provider"]
        logger.info(
            f"STT call: provider={provider} audio_duration={m.audio_duration:.2f}s "
            f"latency={m.duration:.2f}s streamed={m.streamed}"
        )

    frame_count = [0]
    audio_level_log_count = [0]

    def on_vad_metrics(m):
        """Log VAD metrics to verify VAD is running."""
        logger.debug(f"VAD metrics: inference_count={m.inference_count} idle_time={m.idle_time:.2f}s frames={frame_count[0]}")

    async def monitor_audio_from_track(track: rtc.RemoteAudioTrack, participant_identity: str):
        """Monitor audio levels from a specific track."""
        try:
            logger.info(f"Starting audio level monitor for: {participant_identity} track={track.sid}")
            audio_stream = rtc.AudioStream(track)
            async for frame_event in audio_stream:
                frame = frame_event.frame
                rms_db, peak_db = calculate_audio_level(frame)
                audio_level_log_count[0] += 1
                # Log every 50 frames (~1.6s at 30fps)
                if audio_level_log_count[0] % 50 == 0:
                    logger.info(f"Audio level: RMS={rms_db:.1f}dB peak={peak_db:.1f}dB sr={frame.sample_rate} samples={frame.samples_per_channel}")
        except Exception as e:
            logger.error(f"Error monitoring audio: {e}")

    @ctx.room.on("track_subscribed")
    def on_track_subscribed(track: rtc.Track, publication: rtc.TrackPublication, participant: rtc.RemoteParticipant):
        if track.kind == rtc.TrackKind.KIND_AUDIO and isinstance(track, rtc.RemoteAudioTrack):
            logger.info(f"Audio track subscribed: {participant.identity} track={track.sid}")
            asyncio.create_task(monitor_audio_from_track(track, participant.identity))

    def on_user_state_changed(ev: UserStateChangedEvent):
        """Track turn timing for VAD gating metrics."""
        print(f"USER STATE CALLBACK: {ev.old_state} -> {ev.new_state}", flush=True)
        logger.info(f"User state changed: {ev.old_state} -> {ev.new_state}")
        agent = current_agent[0]
        if not agent or not isinstance(agent, ChatAgent):
            logger.warning(f"No ChatAgent available for state change")
            return

        if ev.new_state == "speaking" and ev.old_state != "speaking":
            # User started speaking - begin new turn
            user_speech_start_time[0] = time.time()
            agent.on_speech_start()
        elif ev.old_state == "speaking" and ev.new_state != "speaking":
            # User stopped speaking - end turn
            start_time = user_speech_start_time[0]
            if start_time:
                speech_duration = time.time() - start_time
                agent.on_speech_end(speech_duration)
            user_speech_start_time[0] = None

    def on_session_close(_):
        """Log VAD gating metrics when session closes."""
        agent = current_agent[0]
        if agent and isinstance(agent, ChatAgent):
            agent.log_session_metrics()

    def create_agent(s: dict) -> Agent:
        """Create agent based on current settings."""
        if s["agent_mode"] == "chat":
            agent = ChatAgent(
                stt_provider=s["stt_provider"],
                llm_model=s["llm_model"],
                tts_enabled=s["tts_enabled"],
            )
            agent.set_room(ctx.room)  # Pass room for immediate text streaming
            current_agent[0] = agent
            return agent
        else:
            current_agent[0] = None
            return TranscribeAgent(stt_provider=s["stt_provider"])

    async def _apply_settings(new_settings: dict):
        nonlocal session
        old = current_settings[0]

        # Check what changed
        mode_changed = new_settings["agent_mode"] != old["agent_mode"]
        stt_changed = new_settings["stt_provider"] != old["stt_provider"]
        llm_changed = new_settings["llm_model"] != old["llm_model"]
        tts_changed = new_settings["tts_enabled"] != old["tts_enabled"]

        if not (mode_changed or stt_changed or llm_changed or tts_changed):
            return

        logger.info(f"Settings changed: {old} -> {new_settings}")
        current_settings[0] = new_settings.copy()

        await session.close()
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
        # Register handlers
        session.on("user_state_changed", on_user_state_changed)
        session.on("close", on_session_close)
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
    # Register handlers
    session.on("user_state_changed", on_user_state_changed)
    session.on("close", on_session_close)
    logger.info("Registered user_state_changed and close handlers")
    if session.stt:
        session.stt.on("metrics_collected", on_stt_metrics)
    if session.vad:
        session.vad.on("metrics_collected", on_vad_metrics)
        logger.info("Registered VAD metrics handler")


if __name__ == "__main__":
    cli.run_app(server)
