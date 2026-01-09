import asyncio
import json
import logging
import os
import uuid
from typing import AsyncIterable

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
    room_io,
)
from livekit.agents.voice import ModelSettings
from livekit.plugins import deepgram, elevenlabs, openai, silero
from livekit.plugins.turn_detector.multilingual import MultilingualModel

from constants import TOPIC_LLM_STREAM, ATTR_SEGMENT_ID, ATTR_TRANSCRIPTION_FINAL

load_dotenv()

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
    """Prewarm VAD model for faster startup"""
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

    def create_agent(s: dict) -> Agent:
        """Create agent based on current settings."""
        if s["agent_mode"] == "chat":
            agent = ChatAgent(
                stt_provider=s["stt_provider"],
                llm_model=s["llm_model"],
                tts_enabled=s["tts_enabled"],
            )
            agent.set_room(ctx.room)  # Pass room for immediate text streaming
            return agent
        else:
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


if __name__ == "__main__":
    cli.run_app(server)
