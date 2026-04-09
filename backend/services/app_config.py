"""
Application configuration service.

Manages server-side configuration for system prompt and LLM provider.
This enables configuration to be shared across all clients.
"""

import logging

from models.schemas import AppConfig, AppConfigUpdate

logger = logging.getLogger("chatbot.config")

# ── Singleton Configuration ───────────────────────────────────────────────────

_app_config = AppConfig()


def get_config() -> AppConfig:
    """Return the current application configuration."""
    return _app_config


def update_config(updates: AppConfigUpdate) -> AppConfig:
    """Partially update the application configuration."""
    global _app_config
    update_data = updates.model_dump(exclude_unset=True)
    _app_config = _app_config.model_copy(update=update_data)
    logger.info("App config updated: %s", update_data)
    return _app_config


def reset_config() -> AppConfig:
    """Reset application configuration to defaults."""
    global _app_config
    _app_config = AppConfig()
    logger.info("App config reset to defaults")
    return _app_config
