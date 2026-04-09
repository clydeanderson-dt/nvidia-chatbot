from pydantic import BaseModel, Field
from typing import Optional


# ── Chaos Configuration ───────────────────────────────────────────────────────


class ChaosConfig(BaseModel):
    """Configuration for chaos/fault injection. All fields disabled by default."""

    # LLM-specific failures
    llm_delay_ms: int = Field(default=0, ge=0, description="Delay before LLM response (ms)")
    llm_error_rate: float = Field(default=0.0, ge=0.0, le=1.0, description="Probability of LLM call failure")
    rate_limit_enabled: bool = Field(default=False, description="Enable rate limiting simulation")
    rate_limit_after_n: int = Field(default=5, ge=1, description="Return 429 after N requests")
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


class ChaosConfigUpdate(BaseModel):
    """Partial update model for chaos config — all fields optional."""

    llm_delay_ms: Optional[int] = None
    llm_error_rate: Optional[float] = None
    rate_limit_enabled: Optional[bool] = None
    rate_limit_after_n: Optional[int] = None
    malformed_response_rate: Optional[float] = None
    empty_response_rate: Optional[float] = None
    hallucination_enabled: Optional[bool] = None
    token_limit_error_enabled: Optional[bool] = None
    fixed_delay_ms: Optional[int] = None
    random_delay_min_ms: Optional[int] = None
    random_delay_max_ms: Optional[int] = None
    spike_delay_ms: Optional[int] = None
    spike_probability: Optional[float] = None
    http_500_rate: Optional[float] = None
    http_503_rate: Optional[float] = None
    session_error_rate: Optional[float] = None


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


class StarterResponse(BaseModel):
    suggestions: list[str] = []
