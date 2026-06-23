# Architecture Diagrams

Visual references for the NVIDIA Chatbot system across four lenses:
components, feature flags, observability, and request lifecycle.

For prose-level architecture detail, see
[`architecture.md`](architecture.md).

---

## 1. Components & dependencies

How clients reach the backend and what the backend depends on. The
`X-Client-Type` header is load-bearing — it drives DevCycle audience
targeting and Dynatrace span filtering.

```mermaid
flowchart LR
    subgraph clients["Clients"]
        web["React frontend<br/>(X-Client-Type: web)"]
        mobile["Flutter frontend<br/>(X-Client-Type: mobile)"]
        lg["load_gen.py<br/>(X-Client-Type: load-gen)"]
    end

    subgraph vm["Application VM"]
        nginx["nginx<br/>(reverse proxy)"]
        backend["FastAPI backend<br/>(uvicorn :8000)"]
    end

    subgraph thirdparty["Third-party"]
        nim["NVIDIA NIM<br/>(OpenAI-compatible API)"]
    end

    web -- "HTTPS /api/*" --> nginx
    mobile -- "HTTPS /api/*" --> nginx
    lg -- "HTTPS /api/*" --> nginx
    nginx --> backend
    backend -- "chat completions" --> nim

    classDef client fill:#e3f2fd,stroke:#1976d2,color:#0d1b2a
    classDef infra fill:#f3e5f5,stroke:#7b1fa2,color:#0d1b2a
    classDef external fill:#fff3e0,stroke:#f57c00,color:#0d1b2a
    class web,mobile,lg client
    class nginx,backend infra
    class nim external
```

---

## 2. Feature flags (DevCycle / OpenFeature)

Three flows share the same DevCycle backend:

- **LLM A/B (read)** — backend resolves `llm-model-chat` and
  `llm-model-suggestions` per session, keyed by session ID with
  `clientType` as a custom attribute.
- **Chaos (read)** — backend evaluates chaos flags via OpenFeature.
  The backend is **read-only** for chaos state.
- **Chaos preset (write)** — the scheduled GitHub Actions workflow
  (`.github/workflows/chaos.yml`) mutates DevCycle flag values to apply
  a chaos preset.

Every evaluation emits a `feature_flag.evaluation` **span event** on the
active parent span via the OpenFeature `TracingHook`, which is what makes
flag activity visible in Dynatrace (see diagram 3).

```mermaid
flowchart LR
    subgraph clients["Clients"]
        client["React / Flutter / load_gen<br/>(send session_id + X-Client-Type)"]
    end

    subgraph ga["GitHub"]
        gha["GitHub Actions<br/>chaos.yml (scheduled)"]
    end

    subgraph vm["Application VM"]
        backend["FastAPI backend<br/>OpenFeature + DevCycle SDK<br/>+ TracingHook"]
    end

    subgraph dc["DevCycle"]
        flags["Flags:<br/>llm-model-chat<br/>llm-model-suggestions<br/>chaos-* presets"]
    end

    subgraph llm["LLM"]
        nim["NVIDIA NIM"]
    end

    client -- "/api/chat" --> backend
    backend -- "evaluate (key=session_id,<br/>clientType=web/mobile/load-gen)" --> flags
    flags -. "model name / chaos config" .-> backend
    backend -- "selected model" --> nim

    gha -- "PATCH flag value<br/>(write: chaos preset)" --> flags

    classDef client fill:#e3f2fd,stroke:#1976d2,color:#0d1b2a
    classDef infra fill:#f3e5f5,stroke:#7b1fa2,color:#0d1b2a
    classDef external fill:#fff3e0,stroke:#f57c00,color:#0d1b2a
    classDef ci fill:#e8f5e9,stroke:#388e3c,color:#0d1b2a
    class client client
    class backend infra
    class flags,nim external
    class gha ci
```

---

## 3. Observability

All telemetry funnels through a Bindplane OTel collector before reaching
Dynatrace. RUM bypasses the collector and goes direct from each frontend
to Dynatrace.

```mermaid
flowchart LR
    subgraph clients["Clients"]
        web["React frontend<br/>(frontend.name: AI_Chatbot)"]
        mobile["Flutter frontend<br/>(frontend.name: AI_Chatbot_Flutter)"]
        lg["load_gen.py<br/>(service: chatbot-load-gen)"]
    end

    subgraph vm["Application VM"]
        backend["FastAPI backend<br/>(service: nvidia-chatbot)<br/>OTel SDK + Traceloop"]
    end

    subgraph pipe["Telemetry pipeline"]
        bp["Bindplane<br/>OTel collector"]
    end

    subgraph dt["Dynatrace"]
        dttraces["Traces + Logs"]
        dtrum["RUM<br/>(user.events / user.sessions)"]
    end

    web -- "RUM (direct)" --> dtrum
    mobile -- "RUM (direct)" --> dtrum
    backend -- "OTLP/HTTP" --> bp
    lg -- "OTLP/HTTP" --> bp
    bp -- "OTLP" --> dttraces

    classDef client fill:#e3f2fd,stroke:#1976d2,color:#0d1b2a
    classDef infra fill:#f3e5f5,stroke:#7b1fa2,color:#0d1b2a
    classDef external fill:#fff3e0,stroke:#f57c00,color:#0d1b2a
    classDef pipeStyle fill:#fce4ec,stroke:#c2185b,color:#0d1b2a
    class web,mobile,lg client
    class backend infra
    class dttraces,dtrum external
    class bp pipeStyle
```

---

## 4. Request lifecycle — `POST /api/chat`

End-to-end sequence for a single chat call, including flag evaluation
and telemetry emission. This ties together the previous three diagrams.

```mermaid
%%{init: {'theme':'dark'}}%%
sequenceDiagram
    autonumber
    participant C as Client<br/>(web / mobile / load-gen)
    participant N as nginx
    participant B as FastAPI backend
    participant D as DevCycle
    participant L as NVIDIA NIM
    participant BP as Bindplane collector
    participant DT as Dynatrace

    C->>N: POST /api/chat<br/>(session_id, message,<br/>X-Client-Type)
    N->>B: forward request
    B->>B: start span<br/>chat_response.workflow<br/>(client.type attr)
    B->>D: evaluate llm-model-chat<br/>(key=session_id,<br/>clientType=...)
    D-->>B: model name
    Note over B: TracingHook adds<br/>feature_flag.evaluation<br/>span event
    B->>D: evaluate chaos flags (read)
    D-->>B: chaos config
    B->>L: chat completion<br/>(selected model)
    L-->>B: reply
    B-->>N: 200 OK (reply)
    N-->>C: 200 OK
    B->>BP: export spans / logs (OTLP)
    BP->>DT: forward telemetry
    C->>DT: RUM beacon (direct)
```
