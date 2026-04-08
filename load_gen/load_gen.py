#!/usr/bin/env python3
"""
Continuous load generator for the NVIDIA chatbot API.

Runs indefinitely by default; stops on SIGINT/SIGTERM or when optional
--requests / --duration limits are reached.

Config priority: environment variable > CLI flag > built-in default.

Environment variables:
  LOAD_GEN_URL           Backend base URL   (default: http://localhost:8000)
  LOAD_GEN_CONCURRENCY   Worker count        (default: 5)
  LOAD_GEN_RATE          Target req/s        (default: unset — constant-concurrency mode)
  LOAD_GEN_PROVIDER      LLM provider        (default: nim_api)
"""

import argparse
import asyncio
import math
import os
import signal
import statistics
import sys
import time
from dataclasses import dataclass, field
from typing import Optional
from uuid import uuid4

from dotenv import load_dotenv
load_dotenv()

import httpx
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor

# ---------------------------------------------------------------------------
# OpenTelemetry setup
# ---------------------------------------------------------------------------
def setup_telemetry() -> trace.Tracer:
    """Initialise OTel tracing. Returns a no-op tracer if env vars are absent."""
    endpoint = os.environ.get("DYNATRACE_OTLP_ENDPOINT", "").rstrip("/")
    api_token = os.environ.get("DYNATRACE_API_TOKEN", "")

    if not endpoint or not api_token:
        print(
            "Warning: DYNATRACE_OTLP_ENDPOINT or DYNATRACE_API_TOKEN not set — "
            "telemetry export is disabled.",
            flush=True,
        )
        return trace.get_tracer("load_gen")

    resource = Resource.create({"service.name": "chatbot-load-gen"})
    provider = TracerProvider(resource=resource)
    exporter = OTLPSpanExporter(
        endpoint=f"{endpoint}/v1/traces",
        headers={"Authorization": f"Api-Token {api_token}"},
    )
    provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(provider)

    # Auto-instrument all httpx calls: injects traceparent headers and
    # creates HTTP client spans that link to the backend's server spans.
    HTTPXClientInstrumentor().instrument()

    print(f"Telemetry export enabled → {endpoint}", flush=True)
    return trace.get_tracer("load_gen")


# ---------------------------------------------------------------------------
# Prompt corpus — diverse questions to produce varied Dynatrace traces
# ---------------------------------------------------------------------------
MESSAGES = [
    "Explain how transformers work in machine learning.",
    "What are the key differences between Python lists and tuples?",
    "Write a short poem about the ocean at night.",
    "How does HTTPS protect data in transit?",
    "What is the capital of Australia and what is it known for?",
    "Explain the concept of gradient descent in simple terms.",
    "What are some best practices for securing a REST API?",
    "Give me a brief history of the Linux kernel.",
    "How do I reverse a linked list in Python?",
    "What is the difference between supervised and unsupervised learning?",
    "Explain what a Docker container is and why it's useful.",
    "What causes the northern lights (aurora borealis)?",
    "Write a haiku about software debugging.",
    "How does a binary search tree differ from a hash table?",
    "What is the CAP theorem in distributed systems?",
    "Explain the difference between TCP and UDP protocols.",
    "What is prompt engineering and why does it matter for LLMs?",
    "How do I handle rate limiting when calling external APIs?",
    "What are the main principles of object-oriented programming?",
    "Describe how a neural network learns from training data.",
]

# ---------------------------------------------------------------------------
# Stats
# ---------------------------------------------------------------------------
@dataclass
class Stats:
    total: int = 0
    successes: int = 0
    failures: int = 0
    latencies: list = field(default_factory=list)
    start_time: float = field(default_factory=time.monotonic)

    def record(self, latency: float, success: bool) -> None:
        self.total += 1
        if success:
            self.successes += 1
            self.latencies.append(latency)
        else:
            self.failures += 1

    def percentile(self, p: float) -> float:
        if not self.latencies:
            return 0.0
        sorted_lat = sorted(self.latencies)
        idx = math.ceil(p / 100 * len(sorted_lat)) - 1
        return sorted_lat[max(0, idx)]

    def elapsed(self) -> float:
        return time.monotonic() - self.start_time

    def req_per_sec(self) -> float:
        elapsed = self.elapsed()
        return self.total / elapsed if elapsed > 0 else 0.0


# ---------------------------------------------------------------------------
# Single request
# ---------------------------------------------------------------------------
async def run_one_request(
    client: httpx.AsyncClient,
    base_url: str,
    provider: str,
    stats: Stats,
    tracer: trace.Tracer,
) -> None:
    import random
    session_id = str(uuid4())
    message = random.choice(MESSAGES)

    t0 = time.monotonic()
    success = False
    with tracer.start_as_current_span(
        "load_gen.request",
        attributes={"session.id": session_id, "llm.provider": provider},
    ) as span:
        try:
            resp = await client.post(
                f"{base_url}/api/chat",
                json={
                    "session_id": session_id,
                    "message": message,
                    "provider": provider,
                },
            )
            resp.raise_for_status()
            success = True
            span.set_attribute("http.status_code", resp.status_code)
        except Exception as exc:
            span.record_exception(exc)
        finally:
            latency = time.monotonic() - t0
            stats.record(latency, success)
            span.set_attribute("load_gen.success", success)
            span.set_attribute("load_gen.latency_s", round(latency, 3))

        # Best-effort session cleanup — ignore errors
        try:
            await client.delete(f"{base_url}/api/chat/{session_id}")
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Workers
# ---------------------------------------------------------------------------
async def constant_concurrency_worker(
    client: httpx.AsyncClient,
    base_url: str,
    provider: str,
    stats: Stats,
    stop_event: asyncio.Event,
    max_requests: Optional[int],
    request_counter: list,  # mutable shared counter [int]
    counter_lock: asyncio.Lock,
    tracer: trace.Tracer,
) -> None:
    """One worker that loops continuously until stopped."""
    while not stop_event.is_set():
        if max_requests is not None:
            async with counter_lock:
                if request_counter[0] >= max_requests:
                    break
                request_counter[0] += 1
        await run_one_request(client, base_url, provider, stats, tracer)


async def fixed_rate_dispatcher(
    client: httpx.AsyncClient,
    base_url: str,
    provider: str,
    stats: Stats,
    stop_event: asyncio.Event,
    rate: float,
    concurrency: int,
    max_requests: Optional[int],
    tracer: trace.Tracer,
) -> None:
    """Dispatches requests at a target req/s rate, bounded by concurrency."""
    semaphore = asyncio.Semaphore(concurrency)
    interval = 1.0 / rate
    sent = 0

    async def bounded_request() -> None:
        async with semaphore:
            await run_one_request(client, base_url, provider, stats, tracer)

    while not stop_event.is_set():
        if max_requests is not None and sent >= max_requests:
            break
        asyncio.create_task(bounded_request())
        sent += 1
        await asyncio.sleep(interval)


# ---------------------------------------------------------------------------
# Periodic stats printer
# ---------------------------------------------------------------------------
async def stats_printer(stats: Stats, stop_event: asyncio.Event, interval: int = 30) -> None:
    while not stop_event.is_set():
        try:
            await asyncio.wait_for(
                asyncio.shield(asyncio.ensure_future(stop_event.wait())),
                timeout=interval,
            )
        except asyncio.TimeoutError:
            pass
        _print_periodic(stats)


def _print_periodic(stats: Stats) -> None:
    elapsed = stats.elapsed()
    p50 = stats.percentile(50)
    p95 = stats.percentile(95)
    p99 = stats.percentile(99)
    rps = stats.req_per_sec()
    print(
        f"[+{elapsed:5.0f}s] "
        f"sent={stats.total:<6} ok={stats.successes:<6} err={stats.failures:<4} "
        f"p50={p50:.2f}s  p95={p95:.2f}s  p99={p99:.2f}s  req/s={rps:.2f}",
        flush=True,
    )


# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
def print_summary(stats: Stats) -> None:
    p50 = stats.percentile(50)
    p95 = stats.percentile(95)
    p99 = stats.percentile(99)
    rps = stats.req_per_sec()
    elapsed = stats.elapsed()

    try:
        from rich.console import Console
        from rich.table import Table

        console = Console()
        table = Table(title="Load Generator — Final Summary", show_header=True, header_style="bold cyan")
        table.add_column("Metric", style="bold")
        table.add_column("Value", justify="right")

        table.add_row("Duration", f"{elapsed:.1f}s")
        table.add_row("Total requests", str(stats.total))
        table.add_row("Successes", f"[green]{stats.successes}[/green]")
        table.add_row("Failures", f"[red]{stats.failures}[/red]" if stats.failures else "0")
        table.add_row("Avg req/s", f"{rps:.2f}")
        table.add_row("p50 latency", f"{p50:.3f}s")
        table.add_row("p95 latency", f"{p95:.3f}s")
        table.add_row("p99 latency", f"{p99:.3f}s")

        console.print()
        console.print(table)
    except ImportError:
        print()
        print("=== Load Generator — Final Summary ===")
        print(f"  Duration      : {elapsed:.1f}s")
        print(f"  Total requests: {stats.total}")
        print(f"  Successes     : {stats.successes}")
        print(f"  Failures      : {stats.failures}")
        print(f"  Avg req/s     : {rps:.2f}")
        print(f"  p50 latency   : {p50:.3f}s")
        print(f"  p95 latency   : {p95:.3f}s")
        print(f"  p99 latency   : {p99:.3f}s")


# ---------------------------------------------------------------------------
# Config helpers
# ---------------------------------------------------------------------------
def _env_or(env_key: str, cli_val, default):
    """Return: env var (if set) → CLI value (if not None/False) → default."""
    env = os.environ.get(env_key)
    if env is not None:
        return env
    if cli_val is not None:
        return cli_val
    return default


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Continuous load generator for the NVIDIA chatbot API.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--url", default=None, help="Backend base URL  [env: LOAD_GEN_URL]")
    parser.add_argument("--concurrency", type=int, default=None, help="Worker / max concurrency  [env: LOAD_GEN_CONCURRENCY]")
    parser.add_argument("--rate", type=float, default=None, help="Target req/s (fixed-rate mode)  [env: LOAD_GEN_RATE]")
    parser.add_argument("--provider", default=None, help="LLM provider: nim_api | self_hosted  [env: LOAD_GEN_PROVIDER]")

    stop_group = parser.add_mutually_exclusive_group()
    stop_group.add_argument("--requests", type=int, default=None, help="Stop after N requests")
    stop_group.add_argument("--duration", type=float, default=None, help="Stop after N seconds")

    return parser.parse_args()


async def async_main() -> None:
    args = parse_args()

    base_url: str   = _env_or("LOAD_GEN_URL", args.url, "http://localhost:8000").rstrip("/")
    concurrency: int = int(_env_or("LOAD_GEN_CONCURRENCY", args.concurrency, 5))
    provider: str   = _env_or("LOAD_GEN_PROVIDER", args.provider, "nim_api")
    rate_env         = os.environ.get("LOAD_GEN_RATE")
    rate: Optional[float] = float(rate_env) if rate_env else args.rate

    max_requests: Optional[int] = args.requests
    max_duration: Optional[float] = args.duration

    stats = Stats()
    stop_event = asyncio.Event()
    tracer = setup_telemetry()

    # Signal handlers — cancel immediately (no graceful drain)
    def _handle_signal(*_) -> None:
        print("\nShutting down…", flush=True)
        stop_event.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, _handle_signal)

    print(f"Starting load generator → {base_url}")
    if rate:
        print(f"  Mode        : fixed-rate ({rate} req/s, max concurrency {concurrency})")
    else:
        print(f"  Mode        : constant concurrency ({concurrency} workers)")
    print(f"  Provider    : {provider}")
    if max_requests:
        print(f"  Stop after  : {max_requests} requests")
    elif max_duration:
        print(f"  Stop after  : {max_duration}s")
    else:
        print("  Stop after  : never (SIGINT/SIGTERM to stop)")
    print()

    timeout = httpx.Timeout(60.0)
    tasks: list[asyncio.Task] = []

    async with httpx.AsyncClient(timeout=timeout) as client:
        # Optional duration-based stop
        if max_duration is not None:
            async def _duration_stopper() -> None:
                await asyncio.sleep(max_duration)
                stop_event.set()
            tasks.append(asyncio.create_task(_duration_stopper()))

        # Stats printer
        tasks.append(asyncio.create_task(stats_printer(stats, stop_event, interval=30)))

        if rate:
            tasks.append(asyncio.create_task(
                fixed_rate_dispatcher(client, base_url, provider, stats, stop_event, rate, concurrency, max_requests, tracer)
            ))
            await stop_event.wait()
        else:
            # Constant-concurrency: one task per worker
            counter = [0]
            counter_lock = asyncio.Lock()
            worker_tasks = [
                asyncio.create_task(constant_concurrency_worker(
                    client, base_url, provider, stats, stop_event, max_requests, counter, counter_lock, tracer
                ))
                for _ in range(concurrency)
            ]
            tasks.extend(worker_tasks)

            # Stop when all workers finish (hit max_requests) or stop_event fires
            if max_requests is not None:
                await asyncio.gather(*worker_tasks, return_exceptions=True)
                stop_event.set()
            else:
                await stop_event.wait()

        # Cancel all background tasks
        for t in tasks:
            t.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)

    print_summary(stats)


def main() -> None:
    asyncio.run(async_main())


if __name__ == "__main__":
    main()
