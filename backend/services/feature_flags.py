"""
OpenFeature integration using the DevCycle Python server SDK.
"""

import logging
import os

from devcycle_python_sdk import DevCycleLocalClient, DevCycleLocalOptions
from openfeature import api

logger = logging.getLogger("chatbot.feature_flags")

_devcycle_client: DevCycleLocalClient | None = None
_provider_initialized = False


def initialize_feature_flags() -> None:
    """Initialize OpenFeature with the DevCycle provider."""
    global _devcycle_client, _provider_initialized
    if _provider_initialized:
        return

    sdk_key = os.getenv("DEVCYCLE_SERVER_SDK_KEY")
    if not sdk_key:
        logger.warning(
            "DEVCYCLE_SERVER_SDK_KEY is not set — "
            "DevCycle OpenFeature provider will not be initialized."
        )
        return

    _devcycle_client = DevCycleLocalClient(sdk_key, DevCycleLocalOptions())
    api.set_provider(_devcycle_client.get_openfeature_provider())
    _provider_initialized = True
    logger.info("DevCycle OpenFeature provider initialized")


def get_openfeature_client():
    """Return the OpenFeature client."""
    return api.get_client()


def get_devcycle_client() -> DevCycleLocalClient | None:
    """Return the native DevCycle SDK client (or None if uninitialised)."""
    return _devcycle_client
