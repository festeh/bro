import asyncio
import json
import logging
from dataclasses import dataclass, field
from typing import Any

from dotenv import load_dotenv
from livekit import rtc
from livekit.agents import (
    Agent,
    AgentServer,
    AgentSession,
    AutoSubscribe,
    JobContext,
    JobProcess,
    cli,
    metrics,
    room_io,
)
from livekit.agents.voice import UserStateChangedEvent
from livekit.plugins import silero
from livekit.plugins.turn_detector.multilingual import MultilingualModel

from agent.chat_agent import ChatAgent
from agent.constants import TOPIC_TEXT_INPUT
from agent.settings import AgentSettings, NotificationType, get_settings_from_metadata
from agent.transcribe_agent import TranscribeAgent

load_dotenv()

logger = logging.getLogger("voice-agent")


@dataclass
class SessionState:
    """Mutable state for an agent session."""

    settings: AgentSettings = field(default_factory=AgentSettings)
    agent: "ChatAgent | None" = None
    session: "AgentSession[Any] | None" = None


server = AgentServer(port=8081)


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
        assert state.session is not None
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
        assert state.session is not None
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
        assert state.session is not None
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
