from pydantic import BaseModel, Field


class ChatRequest(BaseModel):
    session_id: str = Field(..., description="Unique identifier for the conversation session")
    message: str = Field(..., description="The user's message")
    system_prompt: str = Field(
        default="You are a helpful, knowledgeable, and friendly AI assistant.",
        description="System prompt / persona for the assistant",
    )
    provider: str = Field(
        default="nim_api",
        description="LLM backend: 'nim_api' for NVIDIA NIM API, 'self_hosted' for self-hosted NIM",
    )


class ChatResponse(BaseModel):
    reply: str
    suggestions: list[str] = []


class HealthResponse(BaseModel):
    status: str


class StarterRequest(BaseModel):
    system_prompt: str = Field(
        default="You are a helpful, knowledgeable, and friendly AI assistant.",
        description="System prompt / persona for the assistant",
    )
    provider: str = Field(
        default="nim_api",
        description="LLM backend: 'nim_api' for NVIDIA NIM API, 'self_hosted' for self-hosted NIM",
    )


class StarterResponse(BaseModel):
    suggestions: list[str] = []
