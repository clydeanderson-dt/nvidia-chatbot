"""
Chaos engineering service.

Provides configurable fault injection including:
- LLM-specific failures (delays, errors, malformed responses)
- Latency injection (fixed, random, spike)
- HTTP error injection (500, 503, session errors)
- Preset profiles for common failure scenarios
"""

import asyncio
import logging
import random
from typing import Optional

from models.schemas import ChaosConfig, ChaosConfigUpdate

logger = logging.getLogger("chatbot.chaos")

# ── Singleton Configuration ───────────────────────────────────────────────────

_chaos_config = ChaosConfig()
_request_count = 0  # For rate limiting simulation


def get_config() -> ChaosConfig:
    """Return the current chaos configuration."""
    return _chaos_config


def update_config(updates: ChaosConfigUpdate) -> ChaosConfig:
    """Partially update the chaos configuration."""
    global _chaos_config
    update_data = updates.model_dump(exclude_unset=True)
    _chaos_config = _chaos_config.model_copy(update=update_data)
    logger.warning("Chaos config updated: %s", update_data)
    return _chaos_config


def reset_config() -> ChaosConfig:
    """Reset chaos configuration to defaults (all disabled)."""
    global _chaos_config, _request_count
    _chaos_config = ChaosConfig()
    _request_count = 0
    logger.info("Chaos config reset to defaults")
    return _chaos_config


# ── Preset Profiles ───────────────────────────────────────────────────────────

PRESETS: dict[str, ChaosConfigUpdate] = {
    "healthy": ChaosConfigUpdate(
        llm_delay_ms=0,
        llm_error_rate=0.0,
        rate_limit_enabled=False,
        malformed_response_rate=0.0,
        empty_response_rate=0.0,
        hallucination_enabled=False,
        token_limit_error_enabled=False,
        fixed_delay_ms=0,
        random_delay_min_ms=0,
        random_delay_max_ms=0,
        spike_delay_ms=0,
        spike_probability=0.0,
        http_500_rate=0.0,
        http_503_rate=0.0,
        session_error_rate=0.0,
    ),
    "slow_llm": ChaosConfigUpdate(
        llm_delay_ms=5000,
    ),
    "flaky_network": ChaosConfigUpdate(
        http_500_rate=0.3,
        random_delay_min_ms=500,
        random_delay_max_ms=2000,
    ),
    "rate_limited": ChaosConfigUpdate(
        rate_limit_enabled=True,
        rate_limit_after_n=3,
    ),
    "degraded": ChaosConfigUpdate(
        llm_error_rate=0.2,
        empty_response_rate=0.1,
        fixed_delay_ms=1000,
    ),
}


def apply_preset(name: str) -> Optional[ChaosConfig]:
    """Apply a named preset profile. Returns None if preset not found."""
    preset = PRESETS.get(name)
    if preset is None:
        return None

    # Always reset first, then apply the preset values on a clean slate
    reset_config()
    if name == "healthy":
        return _chaos_config
    else:
        return update_config(preset)


def list_presets() -> list[str]:
    """Return list of available preset names."""
    return list(PRESETS.keys())


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
    cfg = _chaos_config
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
    cfg = _chaos_config
    if not cfg.rate_limit_enabled:
        return False

    _request_count += 1
    if _request_count > cfg.rate_limit_after_n:
        logger.warning("Chaos: rate limit triggered (request %d > %d)", _request_count, cfg.rate_limit_after_n)
        return True
    return False


def reset_rate_limit_counter() -> None:
    """Reset the rate limit request counter."""
    global _request_count
    _request_count = 0


def is_any_chaos_active() -> bool:
    """Check if any chaos injection is currently enabled."""
    cfg = _chaos_config
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
    cfg = _chaos_config
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
    cfg = _chaos_config
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
    return should_inject(_chaos_config.malformed_response_rate)
