"""
Chaos engineering service.

Provides configurable fault injection including:
- LLM-specific failures (delays, errors, malformed responses)
- Latency injection (fixed, random, spike)
- HTTP error injection (500, 503, session errors)

Configuration is read from DevCycle via OpenFeature; this module is
read-only with respect to chaos state.
"""

import asyncio
import logging
import random

from openfeature.evaluation_context import EvaluationContext

from models.schemas import ChaosConfig
from services.feature_flags import get_openfeature_client

logger = logging.getLogger("chatbot.chaos")

# ── Constants ─────────────────────────────────────────────────────────────────

RATE_LIMIT_THRESHOLD = 3

_CHAOS_CONTEXT = EvaluationContext(targeting_key="server-chaos")

_request_count = 0  # For rate limiting simulation


# ── Configuration ─────────────────────────────────────────────────────────────


def get_config() -> ChaosConfig:
    """Read the current chaos configuration from DevCycle (via OpenFeature)."""
    c = get_openfeature_client()
    return ChaosConfig(
        llm_delay_ms=int(c.get_float_value("chaos-llm-delay-ms", 0, _CHAOS_CONTEXT)),
        llm_error_rate=c.get_float_value("chaos-llm-error-rate", 0.0, _CHAOS_CONTEXT),
        rate_limit_enabled=c.get_boolean_value("chaos-rate-limit-enabled", False, _CHAOS_CONTEXT),
        malformed_response_rate=c.get_float_value("chaos-malformed-response-rate", 0.0, _CHAOS_CONTEXT),
        empty_response_rate=c.get_float_value("chaos-empty-response-rate", 0.0, _CHAOS_CONTEXT),
        hallucination_enabled=c.get_boolean_value("chaos-hallucination-enabled", False, _CHAOS_CONTEXT),
        token_limit_error_enabled=c.get_boolean_value("chaos-token-limit-error-enabled", False, _CHAOS_CONTEXT),
        fixed_delay_ms=int(c.get_float_value("chaos-fixed-delay-ms", 0, _CHAOS_CONTEXT)),
        random_delay_min_ms=int(c.get_float_value("chaos-random-delay-min-ms", 0, _CHAOS_CONTEXT)),
        random_delay_max_ms=int(c.get_float_value("chaos-random-delay-max-ms", 0, _CHAOS_CONTEXT)),
        spike_delay_ms=int(c.get_float_value("chaos-spike-delay-ms", 0, _CHAOS_CONTEXT)),
        spike_probability=c.get_float_value("chaos-spike-probability", 0.0, _CHAOS_CONTEXT),
        http_500_rate=c.get_float_value("chaos-http-500-rate", 0.0, _CHAOS_CONTEXT),
        http_503_rate=c.get_float_value("chaos-http-503-rate", 0.0, _CHAOS_CONTEXT),
        session_error_rate=c.get_float_value("chaos-session-error-rate", 0.0, _CHAOS_CONTEXT),
    )


# ── Chaos Helpers ─────────────────────────────────────────────────────────────


def should_inject(rate: float) -> bool:
    """Return True with the given probability (0.0–1.0)."""
    if rate <= 0.0:
        return False
    if rate >= 1.0:
        return True
    return random.random() < rate


def get_total_delay_ms() -> int:
    """Calculate total delay to inject (fixed + random + spike)."""
    cfg = get_config()
    delay = cfg.fixed_delay_ms

    # Random delay
    if cfg.random_delay_max_ms > cfg.random_delay_min_ms:
        delay += random.randint(cfg.random_delay_min_ms, cfg.random_delay_max_ms)
    elif cfg.random_delay_min_ms > 0:
        delay += cfg.random_delay_min_ms

    # Spike delay
    if cfg.spike_delay_ms > 0 and should_inject(cfg.spike_probability):
        delay += cfg.spike_delay_ms

    return delay


async def inject_delay() -> int:
    """Sleep for the computed delay. Returns the delay in ms."""
    delay_ms = get_total_delay_ms()
    if delay_ms > 0:
        logger.warning("Chaos: injecting delay of %dms", delay_ms)
        await asyncio.sleep(delay_ms / 1000.0)
    return delay_ms


def check_rate_limit() -> bool:
    """Check if rate limit should trigger. Returns True if limit exceeded."""
    global _request_count
    cfg = get_config()
    if not cfg.rate_limit_enabled:
        return False

    _request_count += 1
    if _request_count > RATE_LIMIT_THRESHOLD:
        logger.warning(
            "Chaos: rate limit triggered (request %d > %d)",
            _request_count,
            RATE_LIMIT_THRESHOLD,
        )
        return True
    return False


def reset_rate_limit_counter() -> None:
    """Reset the rate limit request counter."""
    global _request_count
    _request_count = 0


def is_any_chaos_active() -> bool:
    """Check if any chaos injection is currently enabled."""
    cfg = get_config()
    return any(
        [
            cfg.llm_delay_ms > 0,
            cfg.llm_error_rate > 0,
            cfg.rate_limit_enabled,
            cfg.malformed_response_rate > 0,
            cfg.empty_response_rate > 0,
            cfg.hallucination_enabled,
            cfg.token_limit_error_enabled,
            cfg.fixed_delay_ms > 0,
            cfg.random_delay_max_ms > 0,
            cfg.spike_delay_ms > 0,
            cfg.http_500_rate > 0,
            cfg.http_503_rate > 0,
            cfg.session_error_rate > 0,
        ]
    )


# ── Chaos Injection Points ────────────────────────────────────────────────────


class ChaosInjectedError(Exception):
    """Base exception for chaos-injected failures."""

    pass


class ChaosLLMError(ChaosInjectedError):
    """Simulated LLM failure."""

    pass


class ChaosTokenLimitError(ChaosInjectedError):
    """Simulated token/context limit error."""

    pass


class ChaosRateLimitError(ChaosInjectedError):
    """Simulated rate limit error."""

    pass


class ChaosSessionError(ChaosInjectedError):
    """Simulated session corruption/not found error."""

    pass


async def check_pre_llm_chaos() -> dict:
    """
    Check and apply chaos before LLM call.
    Returns dict with chaos metadata for span attributes.
    Raises ChaosInjectedError subclasses on injected failures.
    """
    cfg = get_config()
    chaos_meta = {"chaos.injected": False}

    # Rate limit check
    if check_rate_limit():
        chaos_meta["chaos.injected"] = True
        chaos_meta["chaos.type"] = "rate_limit"
        raise ChaosRateLimitError("Chaos: Rate limit exceeded (429 simulation)")

    # Token limit error
    if cfg.token_limit_error_enabled:
        chaos_meta["chaos.injected"] = True
        chaos_meta["chaos.type"] = "token_limit"
        raise ChaosTokenLimitError("Chaos: Context length exceeded (token limit simulation)")

    # LLM error injection
    if should_inject(cfg.llm_error_rate):
        chaos_meta["chaos.injected"] = True
        chaos_meta["chaos.type"] = "llm_error"
        raise ChaosLLMError("Chaos: Simulated LLM service failure")

    # LLM delay
    if cfg.llm_delay_ms > 0:
        logger.warning("Chaos: injecting LLM delay of %dms", cfg.llm_delay_ms)
        await asyncio.sleep(cfg.llm_delay_ms / 1000.0)
        chaos_meta["chaos.llm_delay_ms"] = cfg.llm_delay_ms

    return chaos_meta


def modify_llm_response(content: str) -> tuple[str, dict]:
    """
    Apply post-LLM chaos modifications to response content.
    Returns (modified_content, chaos_metadata).
    """
    cfg = get_config()
    chaos_meta = {}

    # Empty response injection
    if should_inject(cfg.empty_response_rate):
        logger.warning("Chaos: injecting empty response")
        chaos_meta["chaos.injected"] = True
        chaos_meta["chaos.type"] = "empty_response"
        return "", chaos_meta

    # Hallucination marker injection
    if cfg.hallucination_enabled:
        hallucination_text = (
            "\n\n[HALLUCINATION MARKER: The following information may be fabricated: "
            "The quantum flux capacitor was invented in 1847 by Dr. Fictitious McFakename.]"
        )
        logger.warning("Chaos: injecting hallucination marker")
        chaos_meta["chaos.injected"] = True
        chaos_meta["chaos.type"] = "hallucination"
        return content + hallucination_text, chaos_meta

    return content, chaos_meta


def should_malform_suggestions() -> bool:
    """Check if suggestions should be malformed."""
    return should_inject(get_config().malformed_response_rate)


def get_active_preset_name() -> str:
    """Return the DevCycle variation key currently being served."""
    c = get_openfeature_client()
    return c.get_string_value("chaos-preset-name", "unknown", _CHAOS_CONTEXT)
