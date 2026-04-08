"""
Chat router.

Endpoints:
  GET  /api/health                    — liveness check
  POST /api/chat                      — send a message and return the reply
  DELETE /api/chat/{session_id}       — clear conversation history
"""

import logging

from fastapi import APIRouter
from fastapi.responses import JSONResponse
from opentelemetry import trace

from models.schemas import ChatRequest, ChatResponse, HealthResponse, StarterRequest, StarterResponse
from services.llm import clear_session, get_response, get_starter_suggestions, get_suggestions

logger = logging.getLogger("chatbot.api")
router = APIRouter(prefix="/api")


@router.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    logger.debug("Health check")
    return HealthResponse(status="ok")


@router.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest) -> ChatResponse:
    trace.get_current_span().set_attribute("session.id", request.session_id)
    logger.info(
        "Chat request | session=%s message_len=%d",
        request.session_id,
        len(request.message),
    )
    reply = await get_response(
        session_id=request.session_id,
        message=request.message,
        system_prompt=request.system_prompt,
        provider=request.provider,
    )
    suggestions = await get_suggestions(message=request.message, reply=reply, provider=request.provider)
    logger.info(
        "Chat response | session=%s reply_len=%d suggestions=%d",
        request.session_id,
        len(reply),
        len(suggestions),
    )
    return ChatResponse(reply=reply, suggestions=suggestions)


@router.post("/chat/starters", response_model=StarterResponse)
async def chat_starters(request: StarterRequest) -> StarterResponse:
    logger.debug("Starter suggestions request | system_prompt_len=%d", len(request.system_prompt))
    suggestions = await get_starter_suggestions(system_prompt=request.system_prompt, provider=request.provider)
    return StarterResponse(suggestions=suggestions)


@router.delete("/chat/{session_id}")
async def delete_session(session_id: str) -> dict:
    logger.info("Session cleared | session=%s", session_id)
    clear_session(session_id)
    return {"cleared": session_id}
