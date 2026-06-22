from pydantic import BaseModel, Field
from typing import Optional


# ── Chaos Configuration ───────────────────────────────────────────────────────


class ChaosConfig(BaseModel):
    """Configuration for chaos/fault injection. All fields disabled by default."""

    # LLM-specific failures
    llm_delay_ms: int = Field(default=0, ge=0, description="Delay before LLM response (ms)")
    llm_error_rate: float = Field(default=0.0, ge=0.0, le=1.0, description="Probability of LLM call failure")
    rate_limit_enabled: bool = Field(default=False, description="Enable rate limiting simulation")
    malformed_response_rate: float = Field(
        default=0.0, ge=0.0, le=1.0, description="Probability of malformed JSON in suggestions"
    )
    empty_response_rate: float = Field(default=0.0, ge=0.0, le=1.0, description="Probability of empty LLM response")
    hallucination_enabled: bool = Field(default=False, description="Inject hallucination marker text")
    token_limit_error_enabled: bool = Field(default=False, description="Simulate token/context limit errors")

    # Latency injection
    fixed_delay_ms: int = Field(default=0, ge=0, description="Fixed delay added to all responses (ms)")
    random_delay_min_ms: int = Field(default=0, ge=0, description="Minimum random delay (ms)")
    random_delay_max_ms: int = Field(default=0, ge=0, description="Maximum random delay (ms)")
    spike_delay_ms: int = Field(default=0, ge=0, description="Spike delay amount (ms)")
    spike_probability: float = Field(default=0.0, ge=0.0, le=1.0, description="Probability of spike delay")

    # HTTP error injection
    http_500_rate: float = Field(default=0.0, ge=0.0, le=1.0, description="Probability of HTTP 500 errors")
    http_503_rate: float = Field(default=0.0, ge=0.0, le=1.0, description="Probability of HTTP 503 errors")
    session_error_rate: float = Field(default=0.0, ge=0.0, le=1.0, description="Probability of session errors")


# ── App Configuration ─────────────────────────────────────────────────────────


class AppConfig(BaseModel):
    """Application configuration for system prompt and LLM provider."""

    system_prompt: str = Field(
        default="You are a helpful, knowledgeable, and friendly AI assistant.",
        description="System prompt / persona for the assistant",
    )
    provider: str = Field(
        default="nim_api",
        description="LLM backend: 'nim_api' for NVIDIA NIM API, 'self_hosted' for self-hosted NIM",
    )


class AppConfigUpdate(BaseModel):
    """Partial update model for app config — all fields optional."""

    system_prompt: Optional[str] = None
    provider: Optional[str] = None


# ── Chat Models ───────────────────────────────────────────────────────────────


class ChatRequest(BaseModel):
    session_id: str = Field(..., description="Unique identifier for the conversation session")
    message: str = Field(..., description="The user's message")
    system_prompt: Optional[str] = Field(
        default=None,
        description="System prompt / persona for the assistant (uses server config if not provided)",
    )
    provider: Optional[str] = Field(
        default=None,
        description="LLM backend: 'nim_api' for NVIDIA NIM API, 'self_hosted' for self-hosted NIM (uses server config if not provided)",
    )


class ChatResponse(BaseModel):
    reply: str
    suggestions: list[str] = []
    model: Optional[str] = Field(
        default=None,
        description="LLM model ID that served this reply (resolved via the `llm-model-chat` DevCycle flag).",
    )
    suggestions_model: Optional[str] = Field(
        default=None,
        description="LLM model ID used for follow-up suggestions (resolved via the `llm-model-suggestions` DevCycle flag).",
    )


class HealthResponse(BaseModel):
    status: str


class StarterRequest(BaseModel):
    system_prompt: Optional[str] = Field(
        default=None,
        description="System prompt / persona for the assistant (uses server config if not provided)",
    )
    provider: Optional[str] = Field(
        default=None,
        description="LLM backend: 'nim_api' for NVIDIA NIM API, 'self_hosted' for self-hosted NIM (uses server config if not provided)",
    )
    session_id: Optional[str] = Field(
        default=None,
        description="Session identifier used for feature-flag targeting so starter suggestions use the same LLM model as the chat session.",
    )


class StarterResponse(BaseModel):
    suggestions: list[str] = []
    model: Optional[str] = Field(
        default=None,
        description="LLM model ID resolved for this session (via the `llm-model-chat` DevCycle flag).",
    )
    suggestions_model: Optional[str] = Field(
        default=None,
        description="LLM model ID used to generate the starter suggestions (via the `llm-model-suggestions` DevCycle flag).",
    )
