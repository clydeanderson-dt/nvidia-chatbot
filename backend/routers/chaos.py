"""
Chaos engineering router.

Endpoints for managing chaos/fault injection configuration.
"""

import logging

from fastapi import APIRouter, HTTPException

from models.schemas import ChaosConfig, ChaosConfigUpdate
from services import chaos

logger = logging.getLogger("chatbot.api.chaos")
router = APIRouter(prefix="/api/chaos", tags=["chaos"])


@router.get("", response_model=ChaosConfig)
async def get_chaos_config() -> ChaosConfig:
    """Get the current chaos configuration."""
    return chaos.get_config()


@router.patch("", response_model=ChaosConfig)
async def update_chaos_config(updates: ChaosConfigUpdate) -> ChaosConfig:
    """Partially update the chaos configuration."""
    return chaos.update_config(updates)


@router.post("/reset", response_model=ChaosConfig)
async def reset_chaos_config() -> ChaosConfig:
    """Reset chaos configuration to defaults (all disabled)."""
    return chaos.reset_config()


@router.get("/presets")
async def list_chaos_presets() -> dict:
    """List available chaos preset profiles."""
    return {"presets": chaos.list_presets()}


@router.post("/preset/{name}", response_model=ChaosConfig)
async def apply_chaos_preset(name: str) -> ChaosConfig:
    """Apply a named chaos preset profile."""
    result = chaos.apply_preset(name)
    if result is None:
        raise HTTPException(
            status_code=404,
            detail=f"Preset '{name}' not found. Available: {chaos.list_presets()}",
        )
    logger.warning("Applied chaos preset: %s", name)
    return result


@router.get("/status")
async def get_chaos_status() -> dict:
    """Get chaos status summary."""
    return {
        "active": chaos.is_any_chaos_active(),
        "config": chaos.get_config(),
    }
