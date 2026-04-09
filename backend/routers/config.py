"""
Application configuration router.

Endpoints for managing system prompt and LLM provider settings.
"""

import logging

from fastapi import APIRouter

from models.schemas import AppConfig, AppConfigUpdate
from services import app_config

logger = logging.getLogger("chatbot.api.config")
router = APIRouter(prefix="/api/config", tags=["config"])


@router.get("", response_model=AppConfig)
async def get_app_config() -> AppConfig:
    """Get the current application configuration."""
    return app_config.get_config()


@router.patch("", response_model=AppConfig)
async def update_app_config(updates: AppConfigUpdate) -> AppConfig:
    """Partially update the application configuration."""
    return app_config.update_config(updates)


@router.post("/reset", response_model=AppConfig)
async def reset_app_config() -> AppConfig:
    """Reset application configuration to defaults."""
    return app_config.reset_config()
