import logging
import os
from contextlib import asynccontextmanager

from dotenv import load_dotenv

# Load env vars before Traceloop initialisation so the OTLP endpoint and
# API token are available immediately.
load_dotenv()

from traceloop.sdk import Traceloop  # noqa: E402

_APP_NAME = "nvidia-chatbot"

_traceloop_endpoint = os.getenv("DYNATRACE_OTLP_ENDPOINT")
_traceloop_token = os.getenv("DYNATRACE_API_TOKEN")

if _traceloop_endpoint and _traceloop_token:
    Traceloop.init(
        app_name=_APP_NAME,
        api_endpoint=_traceloop_endpoint,
        headers={"Authorization": f"Api-Token {_traceloop_token}"},
    )
else:
    logging.warning(
        "DYNATRACE_OTLP_ENDPOINT or DYNATRACE_API_TOKEN is not set — "
        "Traceloop/OTel tracing will not be initialised."
    )

# ---------------------------------------------------------------------------
# OTel log pipeline — ships Python logging records to Dynatrace.
# Guarded so the server still starts when Dynatrace vars are absent.
# ---------------------------------------------------------------------------
from opentelemetry import trace as _otel_trace  # noqa: E402
from opentelemetry._logs import set_logger_provider  # noqa: E402
from opentelemetry.instrumentation.logging import LoggingInstrumentor  # noqa: E402
from opentelemetry.sdk._logs import LoggerProvider  # noqa: E402
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor  # noqa: E402

# Re-use the resource already set on the Traceloop-managed TracerProvider so the
# LoggerProvider carries the same service.name (and other attributes) — this is what
# makes logs correlate to the correct service in Dynatrace instead of "unknown_service".
_tracer_provider = _otel_trace.get_tracer_provider()
_otel_resource = getattr(_tracer_provider, "resource", None)

# ---------------------------------------------------------------------------
# Fix gen_ai.system: Traceloop's LangChain instrumentation sets this to
# "Langchain" (the framework), but the OTel GenAI spec says it should identify
# the AI provider. Override it to "nvidia" on every span before export.
# ---------------------------------------------------------------------------
from opentelemetry.sdk.trace import SpanProcessor as _SpanProcessor  # noqa: E402


class _FixGenAiSystemProcessor(_SpanProcessor):
    def on_start(self, span, parent_context=None):
        pass

    def on_end(self, span) -> None:
        attrs = getattr(span, "_attributes", None)
        if attrs is not None and attrs.get("gen_ai.system") == "Langchain":
            attrs["gen_ai.system"] = "nvidia"

    def shutdown(self):
        pass

    def force_flush(self, timeout_millis=30000):
        return True


if hasattr(_tracer_provider, "add_span_processor"):
    _tracer_provider.add_span_processor(_FixGenAiSystemProcessor())

_dt_endpoint = os.getenv("DYNATRACE_OTLP_ENDPOINT")
_dt_token = os.getenv("DYNATRACE_API_TOKEN")

if _dt_endpoint and _dt_token:
    from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter  # noqa: E402

    _log_exporter = OTLPLogExporter(
        endpoint=f"{_dt_endpoint}/v1/logs",
        headers={"Authorization": f"Api-Token {_dt_token}"},
    )
    _logger_provider = LoggerProvider(resource=_otel_resource) if _otel_resource else LoggerProvider()
    _logger_provider.add_log_record_processor(BatchLogRecordProcessor(_log_exporter))
    set_logger_provider(_logger_provider)
else:
    logging.warning(
        "DYNATRACE_OTLP_ENDPOINT or DYNATRACE_API_TOKEN is not set — "
        "logs will not be exported to Dynatrace."
    )

# Bridge Python logging → OTel and inject otelTraceID / otelSpanID into every record.
LoggingInstrumentor().instrument(set_logging_format=True)
# Prevent the DEBUG flood enabled by set_logging_format=True.
logging.getLogger().setLevel(logging.INFO)

logger = logging.getLogger("chatbot.app")

from fastapi import FastAPI  # noqa: E402
from fastapi.middleware.cors import CORSMiddleware  # noqa: E402

from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor  # noqa: E402

from routers.chat import router  # noqa: E402


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Application started | app=%s", _APP_NAME)
    yield
    logger.info("Application shutting down | app=%s", _APP_NAME)


app = FastAPI(title="AI Chatbot API", version="1.0.0", lifespan=lifespan)

FastAPIInstrumentor.instrument_app(app)
logger.info("FastAPI instrumented — HTTP endpoints will create trace spans")

# Parse allowed origins from the environment variable.
# Defaults to localhost dev origins if the variable is not set.
_raw_origins = os.getenv("ALLOWED_ORIGINS", "http://localhost:5173,http://localhost:3000")
allowed_origins = [o.strip() for o in _raw_origins.split(",") if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "DELETE"],
    allow_headers=["Content-Type"],
)

app.include_router(router)
