"""FastAPI WebSocket server for AI chat."""

import json
import uuid
from contextlib import asynccontextmanager

import edge_tts
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import StreamingResponse

from ai.config import settings
from ai.graph import create_app_with_checkpointer, get_history, stream_response
from ai.logging_config import get_server_logger, get_ws_logger, setup_logging

# Initialize logging
setup_logging(json_logs=settings.json_logs, log_level=settings.log_level)
log = get_server_logger()
ws_log = get_ws_logger()

# Global app and checkpointer
app_graph = None
checkpointer_cm = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize the graph and checkpointer on startup."""
    global app_graph, checkpointer_cm

    log.info("starting_server", host=settings.ws_host, port=settings.ws_port)

    try:
        app_graph, checkpointer_cm = await create_app_with_checkpointer()
        log.info("graph_initialized", db_path=settings.db_path)
    except Exception as e:
        log.error("graph_init_failed", error=str(e))
        raise

    yield

    log.info("shutting_down")
    if checkpointer_cm:
        await checkpointer_cm.__aexit__(None, None, None)
        log.debug("checkpointer_closed")


app = FastAPI(title="Bro AI Chat", lifespan=lifespan)


@app.websocket("/ws/{thread_id}")
async def websocket_endpoint(websocket: WebSocket, thread_id: str):
    """WebSocket endpoint for chat communication."""
    await websocket.accept()
    client_host = websocket.client.host if websocket.client else "unknown"

    ws_log.info("ws_connected", thread_id=thread_id, client=client_host)

    # Send history on connect
    try:
        history = await get_history(app_graph, thread_id)
        await websocket.send_json({"type": "history", "messages": history})
        ws_log.debug("history_sent", thread_id=thread_id, message_count=len(history))
    except Exception as e:
        ws_log.error("history_fetch_failed", thread_id=thread_id, error=str(e))
        await websocket.send_json({"type": "error", "message": str(e)})

    try:
        while True:
            data = await websocket.receive_text()
            message = json.loads(data)

            if message.get("type") == "ping":
                await websocket.send_json({"type": "pong"})
                continue

            if message.get("type") == "message":
                content = message.get("content", "")
                provider = message.get("provider")

                if not content:
                    await websocket.send_json(
                        {"type": "error", "message": "Empty message"}
                    )
                    continue

                message_id = str(uuid.uuid4())
                ws_log.info(
                    "message_received",
                    thread_id=thread_id,
                    provider=provider,
                    content_length=len(content),
                    message_id=message_id,
                )

                try:
                    chunk_count = 0
                    conversation_ended = False
                    async for chunk in stream_response(
                        app_graph, thread_id, content, provider
                    ):
                        if isinstance(chunk, dict):
                            # Special event (e.g., conversation_ended)
                            await websocket.send_json(chunk)
                            if chunk.get("type") == "conversation_ended":
                                conversation_ended = True
                        else:
                            await websocket.send_json(
                                {"type": "chunk", "content": chunk}
                            )
                            chunk_count += 1

                    await websocket.send_json(
                        {"type": "done", "message_id": message_id}
                    )

                    if conversation_ended:
                        ws_log.info(
                            "conversation_ended",
                            thread_id=thread_id,
                            message_id=message_id,
                        )
                    ws_log.info(
                        "response_complete",
                        thread_id=thread_id,
                        message_id=message_id,
                        chunks=chunk_count,
                    )
                except Exception as e:
                    ws_log.error(
                        "stream_error",
                        thread_id=thread_id,
                        message_id=message_id,
                        error=str(e),
                    )
                    await websocket.send_json({"type": "error", "message": str(e)})

    except WebSocketDisconnect:
        ws_log.info("ws_disconnected", thread_id=thread_id, client=client_host)
    except Exception as e:
        ws_log.error("ws_error", thread_id=thread_id, error=str(e))
        try:
            await websocket.send_json({"type": "error", "message": str(e)})
        except Exception:
            pass


@app.get("/api/voices")
async def list_voices():
    """List available TTS voices."""
    log.debug("voices_list_requested")
    voices = await edge_tts.list_voices()
    log.debug("voices_fetched", count=len(voices))
    return voices


@app.get("/api/tts")
async def text_to_speech(text: str, voice: str = "en-US-AriaNeural"):
    """Convert text to speech using edge-tts."""
    log.info("tts_requested", voice=voice, text_length=len(text))

    async def generate():
        communicate = edge_tts.Communicate(text, voice)
        async for chunk in communicate.stream():
            if chunk["type"] == "audio":
                yield chunk["data"]

    return StreamingResponse(generate(), media_type="audio/mpeg")


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {"status": "ok"}


if __name__ == "__main__":
    import uvicorn

    log.info("starting_uvicorn", host=settings.ws_host, port=settings.ws_port)
    uvicorn.run(
        "server:app",
        host=settings.ws_host,
        port=settings.ws_port,
        reload=True,
    )
