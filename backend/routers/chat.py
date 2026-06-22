"""
Chat router.

Endpoints:
  GET  /api/health                    — liveness check
  POST /api/chat                      — send a message and return the reply
  POST /api/chat/starters             — get conversation starter suggestions
  DELETE /api/chat/{session_id}       — clear conversation history
"""

import logging

from fastapi import APIRouter, Header, HTTPException
from opentelemetry import trace

from models.schemas import ChatRequest, ChatResponse, HealthResponse, StarterRequest, StarterResponse
from services.llm import (
    clear_session,
    get_response,
    get_starter_suggestions,
    get_suggestions,
    resolve_model,
    resolve_suggestions_model,
)
from services import chaos, app_config

logger = logging.getLogger("chatbot.api")
router = APIRouter(prefix="/api")

# Allowed `X-Client-Type` values. Anything else is normalised to "unknown" so
# the field stays low-cardinality for span/log/audience filtering.
_ALLOWED_CLIENT_TYPES = {"web", "mobile", "load-gen"}


def _normalise_client_type(raw: str | None) -> str:
    if not raw:
        return "unknown"
    value = raw.strip().lower()
    return value if value in _ALLOWED_CLIENT_TYPES else "unknown"


def _check_http_chaos() -> None:
    """Check for HTTP-level chaos injection. Raises ChaosInjectedError if triggered."""
    cfg = chaos.get_config()
    span = trace.get_current_span()

    # HTTP 503 Service Unavailable
    if chaos.should_inject(cfg.http_503_rate):
        span.set_attribute("chaos.injected", True)
        span.set_attribute("chaos.type", "http_503")
        logger.warning("Chaos: injecting HTTP 503")
        raise chaos.ChaosLLMError("HTTP 503 chaos injection")

    # HTTP 500 Internal Server Error
    if chaos.should_inject(cfg.http_500_rate):
        span.set_attribute("chaos.injected", True)
        span.set_attribute("chaos.type", "http_500")
        logger.warning("Chaos: injecting HTTP 500")
        raise chaos.ChaosInjectedError("HTTP 500 chaos injection")

    # Session error
    if chaos.should_inject(cfg.session_error_rate):
        span.set_attribute("chaos.injected", True)
        span.set_attribute("chaos.type", "session_error")
        logger.warning("Chaos: injecting session error")
        raise chaos.ChaosSessionError("Session chaos injection")


def get_chaos_error_message(exc: chaos.ChaosInjectedError) -> tuple[int, str]:
    """Map chaos exception to (status_code, user_friendly_message)."""
    if isinstance(exc, chaos.ChaosRateLimitError):
        return 429, "Rate limit exceeded. Please wait a moment before trying again."
    elif isinstance(exc, chaos.ChaosTokenLimitError):
        return 400, "Your message is too long or the conversation exceeds the model's context limit. Try starting a new conversation."
    elif isinstance(exc, chaos.ChaosSessionError):
        return 404, "Session not found or corrupted. Please refresh the page to start a new session."
    elif isinstance(exc, chaos.ChaosLLMError):
        return 503, "The AI service is temporarily unavailable. Please try again in a moment."
    else:
        return 500, "An unexpected error occurred. Please try again."


@router.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    logger.debug("Health check")
    return HealthResponse(status="ok")


@router.post("/chat", response_model=ChatResponse)
async def chat(
    request: ChatRequest,
    x_client_type: str | None = Header(default=None),
) -> ChatResponse:
    # HTTP-level chaos injection
    _check_http_chaos()

    client_type = _normalise_client_type(x_client_type)
    span = trace.get_current_span()
    span.set_attribute("session.id", request.session_id)
    span.set_attribute("client.type", client_type)

    # Use server-side config as fallback if request doesn't override
    server_config = app_config.get_config()
    system_prompt = request.system_prompt or server_config.system_prompt
    provider = request.provider or server_config.provider

    logger.info(
        "Chat request | session=%s client_type=%s message_len=%d",
        request.session_id,
        client_type,
        len(request.message),
    )
    reply = await get_response(
        session_id=request.session_id,
        message=request.message,
        system_prompt=system_prompt,
        provider=provider,
        client_type=client_type,
    )
    suggestions = await get_suggestions(
        message=request.message,
        reply=reply,
        provider=provider,
        session_id=request.session_id,
        client_type=client_type,
    )
    logger.info(
        "Chat response | session=%s reply_len=%d suggestions=%d",
        request.session_id,
        len(reply),
        len(suggestions),
    )
    return ChatResponse(
        reply=reply,
        suggestions=suggestions,
        model=resolve_model(request.session_id, client_type),
        suggestions_model=resolve_suggestions_model(request.session_id, client_type),
    )


@router.post("/chat/starters", response_model=StarterResponse)
async def chat_starters(
    request: StarterRequest,
    x_client_type: str | None = Header(default=None),
) -> StarterResponse:
    client_type = _normalise_client_type(x_client_type)
    trace.get_current_span().set_attribute("client.type", client_type)

    # Use server-side config as fallback
    server_config = app_config.get_config()
    system_prompt = request.system_prompt or server_config.system_prompt
    provider = request.provider or server_config.provider

    logger.debug(
        "Starter suggestions request | client_type=%s system_prompt_len=%d",
        client_type,
        len(system_prompt),
    )
    suggestions = await get_starter_suggestions(
        system_prompt=system_prompt,
        provider=provider,
        session_id=request.session_id,
        client_type=client_type,
    )
    return StarterResponse(
        suggestions=suggestions,
        model=resolve_model(request.session_id, client_type),
        suggestions_model=resolve_suggestions_model(request.session_id, client_type),
    )


@router.delete("/chat/{session_id}")
async def delete_session(
    session_id: str,
    x_client_type: str | None = Header(default=None),
) -> dict:
    client_type = _normalise_client_type(x_client_type)
    trace.get_current_span().set_attribute("client.type", client_type)
    logger.info("Session cleared | session=%s client_type=%s", session_id, client_type)
    clear_session(session_id)
    return {"cleared": session_id}
