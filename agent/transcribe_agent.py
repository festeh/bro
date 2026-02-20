import logging

from livekit.agents import Agent, StopResponse, llm

from agent.settings import AgentSettings, create_stt

logger = logging.getLogger("voice-agent")


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
