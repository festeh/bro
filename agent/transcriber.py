import asyncio
import json
import logging

from dotenv import load_dotenv

from livekit.agents import (
    Agent,
    AgentServer,
    AgentSession,
    AutoSubscribe,
    JobContext,
    StopResponse,
    cli,
    llm,
    room_io,
)
from livekit.plugins import deepgram, silero

load_dotenv()

logger = logging.getLogger("transcriber")

# Registry of available STT providers
STT_PROVIDERS = {
    "deepgram": lambda: deepgram.STT(model="nova-3"),
    # "elevenlabs": lambda: elevenlabs.STT(),
    # "chutes": lambda: ChutesSTT(),
}


class Transcriber(Agent):
    def __init__(self, stt_provider):
        super().__init__(
            instructions="",
            stt=stt_provider,
        )

    async def on_user_turn_completed(
        self, chat_ctx: llm.ChatContext, new_message: llm.ChatMessage
    ):
        transcript = new_message.text_content
        logger.info(f"Transcribed: {transcript}")
        raise StopResponse()


def get_provider_from_metadata(ctx: JobContext) -> str:
    """Extract STT provider name from participant or room metadata."""
    provider_name = "deepgram"  # default

    # Check remote participants' metadata
    for participant in ctx.room.remote_participants.values():
        if participant.metadata:
            try:
                meta = json.loads(participant.metadata)
                if "stt_provider" in meta:
                    provider_name = meta["stt_provider"]
                    logger.info(
                        f"Using provider from participant {participant.identity}: {provider_name}"
                    )
                    break
            except json.JSONDecodeError:
                pass

    # Also check room metadata as fallback
    if ctx.room.metadata:
        try:
            meta = json.loads(ctx.room.metadata)
            if "stt_provider" in meta:
                provider_name = meta["stt_provider"]
                logger.info(f"Using provider from room metadata: {provider_name}")
        except json.JSONDecodeError:
            pass

    return provider_name


server = AgentServer()


@server.rtc_session()
async def entrypoint(ctx: JobContext):
    logger.info(f"Starting transcriber for room: {ctx.room.name}")
    await ctx.connect(auto_subscribe=AutoSubscribe.AUDIO_ONLY)

    # Get initial provider from metadata
    provider_name = get_provider_from_metadata(ctx)
    provider_factory = STT_PROVIDERS.get(provider_name, STT_PROVIDERS["deepgram"])
    stt = provider_factory()
    logger.info(f"Initial STT provider: {provider_name}")

    session = AgentSession(
        vad=silero.VAD.load(min_silence_duration=0.3),
    )

    # Track current provider for hot-swapping
    current_provider = [provider_name]

    async def _switch_provider(new_provider: str):
        nonlocal session
        logger.info(f"Switching STT provider to: {new_provider}")
        current_provider[0] = new_provider

        # Restart session with new provider
        await session.close()
        new_stt = STT_PROVIDERS[new_provider]()
        session = AgentSession(
            vad=silero.VAD.load(min_silence_duration=0.3),
        )
        await session.start(
            agent=Transcriber(new_stt),
            room=ctx.room,
            room_options=room_io.RoomOptions(
                text_output=True,
                audio_output=False,
            ),
        )

    @ctx.room.on("participant_metadata_changed")
    def on_metadata_changed(participant, prev_metadata):
        if participant.metadata:
            try:
                meta = json.loads(participant.metadata)
                new_provider = meta.get("stt_provider")
                if (
                    new_provider
                    and new_provider in STT_PROVIDERS
                    and new_provider != current_provider[0]
                ):
                    asyncio.create_task(_switch_provider(new_provider))
            except json.JSONDecodeError:
                pass

    await session.start(
        agent=Transcriber(stt),
        room=ctx.room,
        room_options=room_io.RoomOptions(
            text_output=True,
            audio_output=False,
        ),
    )


if __name__ == "__main__":
    cli.run_app(server)
