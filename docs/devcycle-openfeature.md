# DevCycle + OpenFeature in the NVIDIA Chatbot

This document explains how feature flags are implemented in this application
and how the chaos engineering subsystem is driven by them.

- **Flag backend**: [DevCycle](https://devcycle.com/) (local-bucketing server SDK)
- **Flag interface**: [OpenFeature](https://openfeature.dev/) (vendor-neutral SDK)
- **Scope**: Backend (`backend/`) only — frontends never see DevCycle directly;
  they poll the backend's read-only `/api/chaos/status` endpoint.

DevCycle dashboard:
<https://app.devcycle.com/o/org_SeGjnZQOwOYgQWYZ/p/nvidia-chatbot/features/chaos-preset/overview>

---

## Why this architecture

| Concern | Choice |
|---|---|
| All chaos knobs change together as a profile | One DevCycle **feature** (`chaos-preset`) with multiple **variations** |
| Vendor lock-in | OpenFeature abstraction — swap providers by changing one file |
| Low-latency evaluation | DevCycle **local-bucketing** SDK (in-process cache, ~µs per eval) |
| Global chaos, not per-user | Constant `EvaluationContext(targeting_key="server-chaos")` |
| Atomic remote control | GitHub Actions PATCHes the DevCycle Management API |
| Frontend safety | Read-only — only DevCycle (via GH Actions) can mutate state |

---

## DevCycle model

A single feature, `chaos-preset`, holds **15 variables** (delays, error rates,
flags). Each **variation** defines a complete set of values for those variables.
Switching the active variation atomically reconfigures the whole chaos profile.

Variations:

| Variation key | Effect |
|---|---|
| `healthy` | All chaos variables at default (off) |
| `slow-llm` | `chaos-llm-delay-ms=5000` |
| `flaky-network` | `chaos-http-500-rate=0.3`, random delay 500–2000ms |
| `rate-limited` | `chaos-rate-limit-enabled=true` |
| `degraded` | `chaos-llm-error-rate=0.2`, `chaos-empty-response-rate=0.1`, `chaos-fixed-delay-ms=1000` |

Variables (all under `chaos-preset`):

| Key | Type |
|---|---|
| `chaos-llm-delay-ms` | Number |
| `chaos-llm-error-rate` | Number |
| `chaos-rate-limit-enabled` | Boolean |
| `chaos-malformed-response-rate` | Number |
| `chaos-empty-response-rate` | Number |
| `chaos-hallucination-enabled` | Boolean |
| `chaos-token-limit-error-enabled` | Boolean |
| `chaos-fixed-delay-ms` | Number |
| `chaos-random-delay-min-ms` | Number |
| `chaos-random-delay-max-ms` | Number |
| `chaos-spike-delay-ms` | Number |
| `chaos-spike-probability` | Number |
| `chaos-http-500-rate` | Number |
| `chaos-http-503-rate` | Number |
| `chaos-session-error-rate` | Number |

Targeting: `production` environment is active and serves the chosen variation
to **All Users** (the demo treats the whole app as production).

---

## End-to-end flow

```
GitHub Actions ──PATCH──▶ DevCycle Management API
                              │
                              ▼ (~1s SDK poll)
                  DevCycle local-bucketing cache
                              │
                              ▼  client.get_*_value(...)
                  OpenFeature client
                              │
                              ▼
              chaos.get_config() → ChaosConfig
                              │
                              ▼
     check_pre_llm_chaos / modify_llm_response / inject_delay
                              │
                              ▼
                    Chat endpoint behaviour
```

---

## Backend implementation

### 1. Dependencies — `backend/requirements.txt`

```
devcycle-python-server-sdk==3.13.10
openfeature-sdk==0.8.3
```

### 2. Environment variables — `backend/.env`

| Variable | Required | Notes |
|---|---|---|
| `DEVCYCLE_SERVER_SDK_KEY` | No* | If absent, provider is not initialized and all flags fall back to defaults — chaos is effectively off. The server still starts. |

GitHub Actions (CI) additionally needs:

| Secret | Purpose |
|---|---|
| `DEVCYCLE_CLIENT_ID` | OAuth2 client-credentials grant |
| `DEVCYCLE_CLIENT_SECRET` | OAuth2 client-credentials grant |
| `DEVCYCLE_PROJECT_KEY` | `nvidia-chatbot` |

### 3. Provider bootstrap — `backend/services/feature_flags.py`

The DevCycle client is created once and registered as the global OpenFeature
provider. Two accessors are exposed: the OpenFeature client for normal flag
reads, and the native DevCycle client for the one feature OpenFeature can't
give us (the active variation key).

```python
from devcycle_python_sdk import DevCycleLocalClient, DevCycleLocalOptions
from openfeature import api

_devcycle_client: DevCycleLocalClient | None = None
_provider_initialized = False

def initialize_feature_flags() -> None:
    global _devcycle_client, _provider_initialized
    if _provider_initialized:
        return

    sdk_key = os.getenv("DEVCYCLE_SERVER_SDK_KEY")
    if not sdk_key:
        logger.warning("DEVCYCLE_SERVER_SDK_KEY is not set — provider will not be initialized.")
        return

    _devcycle_client = DevCycleLocalClient(sdk_key, DevCycleLocalOptions())
    api.set_provider(_devcycle_client.get_openfeature_provider())
    _provider_initialized = True

def get_openfeature_client():
    return api.get_client()       # vendor-neutral handle

def get_devcycle_client():
    return _devcycle_client       # native handle (for variationKey)
```

Called from `backend/main.py` during FastAPI's lifespan startup:

```python
from services.feature_flags import initialize_feature_flags
# inside lifespan startup
initialize_feature_flags()
```

### 4. Reading flags — `backend/services/chaos.py`

A constant evaluation context (`server-chaos`) makes chaos global rather than
per-user. `get_config()` is called on every request — cheap because DevCycle
does local bucketing (in-process), so evaluations are microseconds.

```python
from openfeature.evaluation_context import EvaluationContext
from services.feature_flags import get_openfeature_client

_CHAOS_CONTEXT = EvaluationContext(targeting_key="server-chaos")

def get_config() -> ChaosConfig:
    c = get_openfeature_client()
    return ChaosConfig(
        # ⚠ Numbers come back as float from DevCycle — use get_float_value + cast.
        llm_delay_ms=int(c.get_float_value("chaos-llm-delay-ms", 0, _CHAOS_CONTEXT)),
        llm_error_rate=c.get_float_value("chaos-llm-error-rate", 0.0, _CHAOS_CONTEXT),
        rate_limit_enabled=c.get_boolean_value("chaos-rate-limit-enabled", False, _CHAOS_CONTEXT),
        empty_response_rate=c.get_float_value("chaos-empty-response-rate", 0.0, _CHAOS_CONTEXT),
        hallucination_enabled=c.get_boolean_value("chaos-hallucination-enabled", False, _CHAOS_CONTEXT),
        http_500_rate=c.get_float_value("chaos-http-500-rate", 0.0, _CHAOS_CONTEXT),
        # ... 9 more variables ...
    )
```

The second argument to each `get_*_value` is the **fallback default**. If
DevCycle is unreachable, the SDK isn't initialized, or the variable doesn't
exist, the default is used silently — the app keeps working with chaos off.

### 5. Using flag values — fault injection

The chaos service exposes simple helpers used by `routers/chat.py`:

```python
async def check_pre_llm_chaos() -> dict:
    cfg = get_config()
    chaos_meta = {"chaos.injected": False}

    if check_rate_limit():                              # cfg.rate_limit_enabled
        raise ChaosRateLimitError("Chaos: Rate limit exceeded (429 simulation)")

    if cfg.token_limit_error_enabled:
        raise ChaosTokenLimitError("Chaos: Context length exceeded")

    if should_inject(cfg.llm_error_rate):               # probabilistic
        raise ChaosLLMError("Chaos: Simulated LLM service failure")

    if cfg.llm_delay_ms > 0:
        await asyncio.sleep(cfg.llm_delay_ms / 1000.0)
        chaos_meta["chaos.llm_delay_ms"] = cfg.llm_delay_ms

    return chaos_meta

def should_inject(rate: float) -> bool:
    if rate <= 0.0: return False
    if rate >= 1.0: return True
    return random.random() < rate
```

### 6. Reading the active variation (DevCycle-native)

OpenFeature's `EvaluationDetails.variant` is **not populated** by DevCycle's
provider, so to surface the active preset name (`"slow-llm"`, etc.) we drop
down to the native DevCycle SDK:

```python
from devcycle_python_sdk.models.user import DevCycleUser

def get_active_preset_name() -> str:
    client = get_devcycle_client()
    if client is None:
        return "unknown"
    user = DevCycleUser(user_id="server-chaos")
    features = client.all_features(user)
    feature = features.get("chaos-preset")
    return feature.variationKey if feature else "unknown"
```

### 7. Read-only HTTP API — `backend/routers/chaos.py`

The backend cannot mutate chaos state. Only three GET endpoints exist:

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/chaos` | Current resolved `ChaosConfig` |
| `GET` | `/api/chaos/status` | `{active, config, preset, controlled_by: "devcycle"}` |
| `GET` | `/api/chaos/presets` | Hardcoded list of variation keys |

```python
@router.get("/status")
async def get_chaos_status() -> dict:
    cfg = chaos.get_config()
    return {
        "active": chaos.is_any_chaos_active(),
        "config": cfg,
        "preset": chaos.get_active_preset_name(),
        "controlled_by": "devcycle",
    }
```

---

## Frontend integration

Both clients are **purely consumers** of `/api/chaos/status`:

- **React** (`frontend/src/context/ConfigContext.jsx`): polls `/api/chaos/status`
  every 5s, exposes `chaosVariation`. The config page renders all chaos
  values as read-only rows with a "🚩 Controlled by DevCycle Feature Flags"
  banner that links to the DevCycle dashboard.
- **Flutter** (`flutter_frontend/lib/providers/config_provider.dart`): same
  pattern — `getChaosStatus()` polled every 5s, read-only display, dashboard
  link via `url_launcher`.

Neither client has any write methods for chaos.

---

## External control — `.github/workflows/chaos.yml`

The only way chaos state changes. DevCycle's Management API uses **OAuth2
client credentials** (no static API tokens), so each run exchanges credentials
for a short-lived bearer token, then PATCHes the production target to a new
variation.

```yaml
- name: Get DevCycle access token
  id: dvc_auth
  run: |
    TOKEN=$(curl -s -X POST https://auth.devcycle.com/oauth/token \
      -H 'content-type: application/x-www-form-urlencoded' \
      -d grant_type=client_credentials \
      -d audience=https://api.devcycle.com/ \
      -d client_id=${{ secrets.DEVCYCLE_CLIENT_ID }} \
      -d client_secret=${{ secrets.DEVCYCLE_CLIENT_SECRET }} \
      | jq -r .access_token)
    echo "::add-mask::$TOKEN"
    echo "token=$TOKEN" >> $GITHUB_OUTPUT

- name: Apply chaos preset via DevCycle
  run: |
    PRESET="${{ steps.preset.outputs.preset }}"   # e.g. "slow-llm"
    curl -X PATCH -f \
      "https://api.devcycle.com/v1/projects/$DEVCYCLE_PROJECT_KEY/features/chaos-preset/configurations?environment=production" \
      -H "Authorization: Bearer ${{ steps.dvc_auth.outputs.token }}" \
      -H "Content-Type: application/json" \
      -d "{\"targets\":[{\"name\":\"All Users - $PRESET\",
            \"distribution\":[{\"_variation\":\"$PRESET\",\"percentage\":1}],
            \"audience\":{\"name\":\"All Users\",
              \"filters\":{\"filters\":[{\"type\":\"all\"}],\"operator\":\"and\"}}}]}"
```

Within ~1s of the PATCH, the backend's local DevCycle cache picks up the new
variation and the next `get_config()` call returns the new values — no
backend redeploy, no API call from the backend itself. A subsequent
`Reset to healthy` step re-fetches a token (with `if: always()`) and PATCHes
the variation back to `healthy`.

---

## Gotchas (read before changing flag code)

1. **Numbers are floats.** DevCycle returns Number variables as `float`.
   OpenFeature's spec strictly type-checks the SDK's returned value against
   the requested Python type, so `get_integer_value(...)` silently falls back
   to the default with `error_code=TYPE_MISMATCH`. Always use
   `get_float_value` and cast with `int(...)` for `*_ms` fields.

2. **`EvaluationDetails.variant` is `None` with DevCycle.** To get the active
   variation key, use the native DevCycle SDK
   (`client.all_features(user)["chaos-preset"].variationKey`). That's what
   `get_active_preset_name()` does.

3. **`targeting_key` is a constant.** We use `"server-chaos"` so chaos
   applies globally. For per-session chaos in the future, pass `session_id`
   as the targeting key.

4. **Local-bucketing latency is microseconds**, so re-evaluating on every
   request is fine — no extra caching layer needed.

5. **Update propagation is ~1s** after a Management API PATCH. Don't expect
   instant atomic switching in sub-second tests.

6. **Adding a new variable** mid-process: the local-bucketing cache may not
   include the new key until its next poll (~30s). A backend restart
   guarantees freshness during dev.

7. **OAuth2 only.** DevCycle Management API has no static API tokens. Tokens
   expire in ~24h, so the workflow fetches a fresh one per run.

8. **No backend writes.** All `PATCH /api/chaos`, `POST /api/chaos/reset`,
   and `POST /api/chaos/preset/{name}` endpoints were removed. DevCycle is
   the only source of truth.

---

## Swapping providers (the OpenFeature payoff)

To move off DevCycle, only `backend/services/feature_flags.py` changes:
register a different OpenFeature provider in `initialize_feature_flags()`.
All `get_float_value` / `get_boolean_value` calls in `chaos.py` keep
working unchanged. The one DevCycle-specific bit — `get_active_preset_name()`
using `all_features(...).variationKey` — would need an equivalent on the
new provider (or replace it with a dedicated string variable).

