"""
LangChain integration with NVIDIA NIM.

Session history is kept in memory (dict keyed by session_id).
Each request is handled by ainvoke(), returning the full response as a string.
"""

import json as _json
import logging
import os
import time
from pathlib import Path

from opentelemetry import trace as _otel_trace

from dotenv import load_dotenv
from langchain_core.chat_history import BaseChatMessageHistory
from langchain_core.messages import SystemMessage
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
from langchain_core.runnables.history import RunnableWithMessageHistory
from langchain_community.chat_message_histories import ChatMessageHistory
from langchain_nvidia_ai_endpoints import ChatNVIDIA
from openfeature.evaluation_context import EvaluationContext
from traceloop.sdk.decorators import task, workflow

from services import chaos
from services.feature_flags import get_openfeature_client

# Repo-root .env — see backend/main.py for the rationale.
load_dotenv(Path(__file__).resolve().parents[2] / ".env")

logger = logging.getLogger("chatbot.llm")

# Fallback model used when the `llm-model` DevCycle flag cannot be evaluated
# (e.g. DevCycle SDK not initialised, flag missing, or self-hosted NIM where
# the model is fixed by the deployed container).
_DEFAULT_MODEL = "meta/llama-3.1-8b-instruct"
_LLM_MODEL_FLAG = "llm-model"

# ── LLM client initialisation ─────────────────────────────────────────────────
_nvidia_api_key = os.getenv("NVIDIA_API_KEY")
_self_hosted_nim_url = os.getenv("SELF_HOSTED_NIM_URL")

# Cache of ChatNVIDIA instances keyed by (provider, model). Instances are
# created lazily on first use so we don't pay the cost for unused variations.
_llm_cache: dict[tuple[str, str], ChatNVIDIA] = {}


def resolve_model(session_id: str | None) -> str:
    """Resolve the model ID for a session via the `llm-model` DevCycle flag.

    Uses `session_id` as the OpenFeature targeting key so each session sticks
    to one model across requests. Falls back to `_DEFAULT_MODEL` if OpenFeature
    is not initialised or evaluation fails.
    """
    try:
        client = get_openfeature_client()
        ctx = EvaluationContext(targeting_key=session_id or "anonymous")
        return client.get_string_value(_LLM_MODEL_FLAG, _DEFAULT_MODEL, ctx)
    except Exception as exc:
        logger.warning("Failed to resolve %s flag: %s", _LLM_MODEL_FLAG, exc)
        return _DEFAULT_MODEL


def _get_llm(provider: str, model: str) -> ChatNVIDIA | None:
    """Return a cached ChatNVIDIA client for (provider, model), or None if the
    provider is not configured.

    Self-hosted NIM serves a single model from its deployed container, so the
    `model` argument is ignored for that provider and the default is used.
    """
    if provider == "nim_api":
        if not _nvidia_api_key:
            return None
        key = (provider, model)
        if key not in _llm_cache:
            _llm_cache[key] = ChatNVIDIA(model=model, api_key=_nvidia_api_key)
        return _llm_cache[key]
    if provider == "self_hosted":
        if not _self_hosted_nim_url:
            return None
        key = (provider, _DEFAULT_MODEL)
        if key not in _llm_cache:
            _llm_cache[key] = ChatNVIDIA(
                model=_DEFAULT_MODEL,
                base_url=f"{_self_hosted_nim_url.rstrip('/')}/v1",
                api_key="not-required",
            )
        return _llm_cache[key]
    return None

# In-memory session store: { session_id -> ChatMessageHistory }
_session_store: dict[str, ChatMessageHistory] = {}


def _get_session_history(session_id: str) -> BaseChatMessageHistory:
    if session_id not in _session_store:
        _session_store[session_id] = ChatMessageHistory()
    return _session_store[session_id]


def clear_session(session_id: str) -> None:
    """Remove all message history for a session."""
    _session_store.pop(session_id, None)


def _build_chain(system_prompt: str, provider: str, model: str):
    """Build a RunnableWithMessageHistory chain for the given system prompt, provider, and model."""
    llm = _get_llm(provider, model)
    if llm is None:
        if provider == "nim_api":
            raise RuntimeError("NVIDIA_API_KEY is not set in the environment.")
        elif provider == "self_hosted":
            raise RuntimeError("SELF_HOSTED_NIM_URL is not configured.")
        else:
            raise ValueError(f"Unknown LLM provider: {provider!r}")

    prompt = ChatPromptTemplate.from_messages(
        [
            SystemMessage(content=system_prompt),
            MessagesPlaceholder(variable_name="history"),
            ("human", "{input}"),
        ]
    )

    chain = prompt | llm

    return RunnableWithMessageHistory(
        chain,
        _get_session_history,
        input_messages_key="input",
        history_messages_key="history",
    )


@workflow(name="chat_response")
async def get_response(
    session_id: str,
    message: str,
    system_prompt: str,
    provider: str = "nim_api",
) -> str:
    """Invoke the chain and return the assistant reply as a plain string."""
    span = _otel_trace.get_current_span()
    span.set_attribute("session.id", session_id)
    model = resolve_model(session_id)
    span.set_attribute("llm.model", model)
    logger.info(
        "LLM request  | session=%s  model=%s  provider=%s  message_len=%d",
        session_id,
        model,
        provider,
        len(message),
    )

    # ── Pre-LLM Chaos Injection ───────────────────────────────────────────────
    chaos_meta = await chaos.check_pre_llm_chaos()
    for key, value in chaos_meta.items():
        span.set_attribute(key, value)

    # ── Latency Injection ─────────────────────────────────────────────────────
    delay_ms = await chaos.inject_delay()
    if delay_ms > 0:
        span.set_attribute("chaos.delay_ms", delay_ms)
        span.set_attribute("chaos.injected", True)

    chain = _build_chain(system_prompt, provider, model)
    config = {"configurable": {"session_id": session_id}}
    start = time.perf_counter()

    try:
        result = await chain.ainvoke({"input": message}, config=config)
        elapsed = time.perf_counter() - start

        # ── Post-LLM Chaos Modification ───────────────────────────────────────
        content, post_chaos_meta = chaos.modify_llm_response(result.content)
        for key, value in post_chaos_meta.items():
            span.set_attribute(key, value)

        logger.info(
            "LLM response | session=%s  elapsed=%.2fs",
            session_id,
            elapsed,
        )
        return content
    except Exception as exc:
        elapsed = time.perf_counter() - start
        logger.error(
            "LLM error    | session=%s  elapsed=%.2fs  error=%s",
            session_id,
            elapsed,
            exc,
        )
        raise


@task(name="chat_suggestions")
async def get_suggestions(
    message: str,
    reply: str,
    provider: str = "nim_api",
    session_id: str | None = None,
) -> list[str]:
    """Generate 2-3 follow-up question suggestions for the last conversation turn.

    Returns an empty list on any failure so the chat is never broken.
    """
    model = resolve_model(session_id)
    llm = _get_llm(provider, model)
    if llm is None:
        return []

    # ── Chaos: Malformed Response Injection ───────────────────────────────────
    if chaos.should_malform_suggestions():
        logger.warning("Chaos: returning malformed suggestions JSON")
        return []  # Simulates JSON parse failure by returning empty

    prompt = (
        "Given the following exchange, suggest exactly 3 short follow-up questions "
        "the user might want to ask next. "
        "Reply with ONLY a valid JSON array of 3 strings and nothing else.\n\n"
        f"User: {message}\n"
        f"Assistant: {reply}"
    )

    try:
        result = await llm.ainvoke(prompt)
        content = result.content.strip()
        # Strip optional markdown code fences
        if content.startswith("```"):
            lines = content.splitlines()
            content = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:])
        suggestions = _json.loads(content.strip())
        if isinstance(suggestions, list):
            return [str(s) for s in suggestions[:3]]
        return []
    except Exception as exc:
        logger.warning("Suggestion generation failed: %s", exc)
        return []


@task(name="chat_starter_suggestions")
async def get_starter_suggestions(
    system_prompt: str,
    provider: str = "nim_api",
    session_id: str | None = None,
) -> list[str]:
    """Generate 3 opening question suggestions for a fresh session.

    Uses the system prompt to tailor suggestions to the assistant's role.
    Returns an empty list on any failure so the chat is never broken.
    """
    model = resolve_model(session_id)
    llm = _get_llm(provider, model)
    if llm is None:
        return []

    role_context = (
        f"The assistant's role is described as: {system_prompt}"
        if system_prompt.strip()
        else "The assistant is a general-purpose AI assistant."
    )

    prompt = (
        f"{role_context}\n\n"
        "Suggest exactly 3 short, distinct opening questions a new user might want to ask this assistant. "
        "Reply with ONLY a valid JSON array of 3 strings and nothing else."
    )

    try:
        result = await llm.ainvoke(prompt)
        content = result.content.strip()
        # Strip optional markdown code fences
        if content.startswith("```"):
            lines = content.splitlines()
            content = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:])
        suggestions = _json.loads(content.strip())
        if isinstance(suggestions, list):
            return [str(s) for s in suggestions[:3]]
        return []
    except Exception as exc:
        logger.warning("Starter suggestion generation failed: %s", exc)
        return []
