"""
Chaos engineering router.

Read-only endpoints exposing chaos state. Configuration is managed
externally via DevCycle feature flags.
"""

import logging

from fastapi import APIRouter

from models.schemas import ChaosConfig
from services import chaos

logger = logging.getLogger("chatbot.api.chaos")
router = APIRouter(prefix="/api/chaos", tags=["chaos"])

PRESET_NAMES = ["healthy", "slow-llm", "flaky-network", "rate-limited", "degraded"]


@router.get("", response_model=ChaosConfig)
async def get_chaos_config() -> ChaosConfig:
    """Get the current chaos configuration (resolved from DevCycle)."""
    return chaos.get_config()


@router.get("/presets")
async def list_chaos_presets() -> dict:
    """List available chaos preset profiles (DevCycle variation keys)."""
    return {"presets": PRESET_NAMES}


@router.get("/status")
async def get_chaos_status() -> dict:
    """Get chaos status summary."""
    cfg = chaos.get_config()
    return {
        "active": chaos.is_any_chaos_active(),
        "config": cfg,
        "preset": chaos.get_active_preset_name(),
        "controlled_by": "devcycle",
    }
