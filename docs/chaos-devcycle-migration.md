# Chaos Engineering → DevCycle Feature Flags Migration

**Branch**: `agents-refactor-chaos-engineering-feature-flags`
**Status**: Phase 2 (backend) complete ✅ — Phase 3 (React + Flutter) complete ✅ — Phase 4–5 pending
**Owner notes**: Plan locked in across 2026-06-17 session. Resume from "Execution Checklist" below.

---

## Decisions Locked In

| Decision | Value |
|---|---|
| Modeling | Option B — single feature with variations as presets |
| Frontend chaos UI | Read-only; add "🚩 Controlled by DevCycle Feature Flags" banner |
| Target environment | `production` only (app is always "production" for demo) |
| `rate_limit_after_n` | Removed from config; hardcode `RATE_LIMIT_THRESHOLD = 3` in `chaos.py` |
| DevCycle project | `nvidia-chatbot` (org: `org_SeGjnZQOwOYgQWYZ`) |

Dashboard: https://app.devcycle.com/o/org_SeGjnZQOwOYgQWYZ/p/nvidia-chatbot/features/chaos-preset/overview

---

## DevCycle State (already created via MCP)

**Feature**: `chaos-preset` (type: `ops`, server-only SDK visibility, tags: `chaos`, `demo`)

**Variations** (15 variables per variation; values below are the non-zero/non-false ones). The currently-served variation key is read at runtime via OpenFeature `EvaluationDetails.variant` (DevCycle's OpenFeature provider populates this with the variation key) — no dedicated label variable is needed.
- `healthy` — all chaos variables at default
- `slow-llm` — `chaos-llm-delay-ms=5000`
- `flaky-network` — `chaos-http-500-rate=0.3`, `chaos-random-delay-min-ms=500`, `chaos-random-delay-max-ms=2000`
- `rate-limited` — `chaos-rate-limit-enabled=true`
- `degraded` — `chaos-llm-error-rate=0.2`, `chaos-empty-response-rate=0.1`, `chaos-fixed-delay-ms=1000`

**Variables** (15 total, all created under `chaos-preset`):
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

`chaos-preset` was 16 vars in an earlier plan with a dedicated `chaos-preset-name` String variable, but that's now removed — the backend uses OpenFeature `EvaluationDetails.variant` instead.

**Targeting**:
- `development`: active, serves `healthy` to All Users
- `staging`: inactive
- `production`: active, serves `healthy` to All Users
- `controlVariation`: `healthy`

---

## Existing Scaffolding in Codebase

Already in place — don't duplicate:
- `backend/requirements.txt` — `devcycle-python-server-sdk==3.13.10`, `openfeature-sdk==0.8.3`
- `backend/services/feature_flags.py` — initializes `DevCycleLocalClient` and registers as OpenFeature provider when `DEVCYCLE_SERVER_SDK_KEY` env var is set
- `backend/main.py` — lifespan calls `initialize_feature_flags()` on startup

The DevCycle client is wired in but nothing reads from it yet. That's the work.

---

## Execution Checklist

### Manual setup (user)
- [x] Get the production **server SDK key** from DevCycle dashboard → add as `DEVCYCLE_SERVER_SDK_KEY` env var on deployed backend (and locally in `backend/.env`).
- [ ] Generate a **Management API token** in DevCycle → add to GitHub repo secrets as `DEVCYCLE_API_TOKEN`.
- [ ] Add GitHub repo secret `DEVCYCLE_PROJECT_KEY=nvidia-chatbot`.

### Phase 2 — Backend refactor ✅ DONE

Completed:
- `backend/models/schemas.py` — removed `rate_limit_after_n` field and the now-unused `ChaosConfigUpdate` model.
- `backend/services/chaos.py` — added `RATE_LIMIT_THRESHOLD = 3` constant; replaced singleton `_chaos_config` with `get_config()` that reads from OpenFeature on every call; added `get_active_preset_name()` that uses the native DevCycle SDK (`all_features(user)["chaos-preset"].variationKey`); deleted `update_config`, `reset_config`, `apply_preset`, `list_presets`, `PRESETS`; updated `check_rate_limit()` to use the threshold constant; left all helpers (`should_inject`, `get_total_delay_ms`, `inject_delay`, `is_any_chaos_active`, `check_pre_llm_chaos`, `modify_llm_response`, `should_malform_suggestions`, all `ChaosInjectedError` subclasses) unchanged.
- `backend/services/feature_flags.py` — added `get_devcycle_client()` accessor for the native SDK client, used by `get_active_preset_name()`.
- `backend/routers/chaos.py` — kept `GET /api/chaos`, `GET /api/chaos/status`, `GET /api/chaos/presets`; removed `PATCH /api/chaos`, `POST /api/chaos/reset`, `POST /api/chaos/preset/{name}`. `/status` now returns `{active, config, preset, controlled_by: "devcycle"}`. Presets list is hardcoded as `["healthy","slow-llm","flaky-network","rate-limited","degraded"]`.
- `backend/routers/chat.py` & `backend/services/llm.py`: untouched.
- `backend/.env.example`: `DEVCYCLE_SERVER_SDK_KEY` already present.
- `backend/README.md`: chaos section rewritten as read-only/DevCycle-managed.

### Phase 3 — Frontend cleanup

**React (`frontend/src/`)** — ✅ DONE:
- [x] `context/ConfigContext.jsx`: polls `GET /api/chaos/status`, exposes `chaosVariation` (renamed from `chaosPreset`). All write methods (`updateChaosConfig`, `resetChaosConfig`, `applyPreset`) and the `chaosPresets` list are removed.
- [x] `pages/ConfigPage.jsx`: top banner displays the active DevCycle variation name. "Chaos Presets" section deleted. LLM Failures / Latency Injection / HTTP Errors sections converted to read-only display rows via a `ReadOnlyRow` helper. DevCycle banner with dashboard link added.
- [x] `pages/ConfigPage.module.css`: dead styles removed (`.presetGrid`, `.presetBtn*`, `.presetName`, `.presetDesc`, `.activeIndicator`, `.resetBtn`, `.slider`, `.checkboxField`, `.checkboxLabel`, `.rangeGroup`, `.numberInput`). New styles added for `.devcycleBanner`, `.devcycleVariationRow`, `.variationBadge`, `.readonlyRow`.
- [x] `components/chaos-banner` / `ChatPage` banner: kept — still reflects active state from polled status.

**Flutter (`flutter_frontend/lib/`)** — ✅ DONE:
- [x] `models/chaos_config.dart`: removed `rateLimitAfterN` field, deleted `ChaosPreset` class and `chaosPresets` list, added `ChaosStatus` wrapper class for the `/api/chaos/status` payload.
- [x] `services/api_service.dart`: replaced `getChaosConfig` with `getChaosStatus()` hitting `/api/chaos/status`; removed `patchChaosConfig`, `resetChaosConfig`, `applyChaosPreset`.
- [x] `providers/config_provider.dart`: surfaces `chaosVariation` (from `status.preset`); `loadConfig` and `refreshChaosConfig` both read `/api/chaos/status`; all chaos write methods (`updateChaosConfig`, `resetChaosConfig`, `applyChaosPreset`) removed.
- [x] `screens/config_screen.dart`: drops presets grid; LLM Failures / Latency Injection / HTTP Errors sections converted to read-only display rows via `_ReadOnlyRow` helper; chaos-active banner shows variation name; DevCycle banner with dashboard link (via `url_launcher`) added.
- [x] Deleted widgets: `chaos_preset_buttons.dart`, `llm_failures_section.dart`, `latency_injection_section.dart`, `http_errors_section.dart`.
- [x] Kept `widgets/chaos_banner.dart`.
- [x] `pubspec.yaml`: added `url_launcher: ^6.3.0` for opening the DevCycle dashboard link.

### Phase 4 — GitHub Actions

**`.github/workflows/chaos.yml`** — replace preset apply + reset steps:

```yaml
- name: Apply chaos preset via DevCycle
  if: steps.decision.outputs.start == 'true'
  env:
    DEVCYCLE_API_TOKEN: ${{ secrets.DEVCYCLE_API_TOKEN }}
    DEVCYCLE_PROJECT_KEY: ${{ secrets.DEVCYCLE_PROJECT_KEY }}
  run: |
    PRESET="${{ steps.preset.outputs.preset }}"
    curl -X PATCH -f \
      "https://api.devcycle.com/v1/projects/$DEVCYCLE_PROJECT_KEY/features/chaos-preset/configurations?environment=production" \
      -H "Authorization: $DEVCYCLE_API_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"targets\":[{\"name\":\"All Users - $PRESET\",\"distribution\":[{\"_variation\":\"$PRESET\",\"percentage\":1}],\"audience\":{\"name\":\"All Users\",\"filters\":{\"filters\":[{\"type\":\"all\"}],\"operator\":\"and\"}}}]}"

- name: Reset to healthy
  if: always() && steps.decision.outputs.start == 'true'
  env:
    DEVCYCLE_API_TOKEN: ${{ secrets.DEVCYCLE_API_TOKEN }}
    DEVCYCLE_PROJECT_KEY: ${{ secrets.DEVCYCLE_PROJECT_KEY }}
  run: |
    curl -X PATCH -f \
      "https://api.devcycle.com/v1/projects/$DEVCYCLE_PROJECT_KEY/features/chaos-preset/configurations?environment=production" \
      -H "Authorization: $DEVCYCLE_API_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"targets":[{"name":"All Users - Healthy","distribution":[{"_variation":"healthy","percentage":1}],"audience":{"name":"All Users","filters":{"filters":[{"type":"all"}],"operator":"and"}}}]}'
```

- [ ] Update preset names in the bash array — change underscores to dashes to match DevCycle variation keys:
  ```bash
  PRESETS=("slow-llm" "flaky-network" "rate-limited" "degraded")
  ```
- [ ] Update the `case "$PRESET" in` block (Dynatrace event description) to match new dashed names.
- [ ] Remove `BACKEND_URL` references from this workflow (no longer needed).
- [ ] Keep all Dynatrace event-ingest steps unchanged.

### Phase 5 — Validation
- [ ] Local: `pip install -r backend/requirements.txt`, set `DEVCYCLE_SERVER_SDK_KEY` in `backend/.env`, start uvicorn.
- [ ] `curl localhost:8000/api/chaos` should return defaults (all zeros, healthy state).
- [ ] In DevCycle dashboard, manually switch production target distribution to `degraded` variation.
- [ ] Within ~1s, `curl localhost:8000/api/chaos/status` should show `active: true` with degraded values.
- [ ] Switch back to `healthy`.
- [ ] Trigger workflow with `workflow_dispatch` → verify DevCycle audit log shows the PATCH.
- [ ] Confirm Dynatrace events still appear with new dashed preset names.

---

## Important Notes / Gotchas

1. **Preset key naming**: DevCycle variation keys use dashes (`slow-llm`), but the existing Python code and Dynatrace event payloads use underscores (`slow_llm`). The workflow needs translation OR both need to be aligned to dashes. Recommendation: switch all to dashes since DevCycle keys can't easily be changed.

2. **OpenFeature value methods — DevCycle Number variables come back as float**: Do not use `get_integer_value` for any DevCycle Number variable. The OpenFeature spec strictly type-checks the SDK's returned value against the requested Python type, and DevCycle's bucketing returns Numbers as `float`. `get_integer_value` will silently fall back to the default value with `error_code=TYPE_MISMATCH`. Use `get_float_value` and cast with `int(...)` when the field is logically an integer (e.g. `*_ms` fields). Booleans and Strings work normally with their typed accessors.

2a. **OpenFeature `EvaluationDetails.variant` is not populated by the DevCycle provider** — `c.get_boolean_details(...).variant` returns `None`. To read the served variation key, use the native DevCycle SDK: `devcycle_client.all_features(user)["chaos-preset"].variationKey`. `services/feature_flags.py` exposes `get_devcycle_client()` for this purpose.

3. **EvaluationContext targeting_key**: We use a constant `"server-chaos"` so chaos always applies globally. If you ever want per-session chaos, pass `session_id` as the targeting key instead.

4. **DevCycle local-bucketing latency**: SDK caches config in-process; per-request evaluation is microseconds. No additional caching layer needed.

5. **Update propagation**: ~1s after a Management API PATCH, the SDK polls and picks up the change. Don't expect instant atomic switching in sub-second tests.

6. **New variables require a backend restart in some cases**: If you add a new variable to the feature *after* the SDK has already fetched config, the local-bucketing cache may not include the new key until its next poll (usually within ~30s, but a backend restart guarantees freshness during dev).

7. **Active variation display**: The backend reads the currently-served variation key via the native DevCycle SDK (`all_features(user)["chaos-preset"].variationKey`). `GET /api/chaos/status` exposes it as `preset` in the response payload (kept for back-compat), and the React UI surfaces it as "variation". No dedicated `chaos-preset-name` variable is required.

8. **`AGENTS.md` updates**: After full implementation (Phase 3+), update the "API Endpoints" table in `AGENTS.md` to remove deleted PATCH/reset/preset endpoints, and add `preset` + `controlled_by` to the status response shape.

---

## Files Touched (anticipated diff scope)

| File | Change |
|---|---|
| `backend/models/schemas.py` | Removed `rate_limit_after_n` field; removed `ChaosConfigUpdate` |
| `backend/services/chaos.py` | Rewrote config layer to read DevCycle via OpenFeature; added `get_active_preset_name()`; kept helpers |
| `backend/routers/chaos.py` | Removed write endpoints; added `preset` + `controlled_by` to `/status` |
| `backend/.env.example` | `DEVCYCLE_SERVER_SDK_KEY` already present |
| `backend/README.md` | Chaos section rewritten as read-only/DevCycle-managed |
| `frontend/src/context/ConfigContext.jsx` | Polls `/api/chaos/status`; exposes `chaosVariation`; write methods removed |
| `frontend/src/pages/ConfigPage.jsx` | Presets grid removed; field groups converted to read-only `ReadOnlyRow` display; DevCycle banner + dashboard link added; "variation" terminology |
| `frontend/src/pages/ConfigPage.module.css` | Dead preset/slider/checkbox/range styles removed; added `.devcycleBanner`, `.devcycleVariationRow`, `.variationBadge`, `.readonlyRow` |
| `flutter_frontend/lib/models/chaos_config.dart` | Removed `rateLimitAfterN`, deleted `ChaosPreset`/`chaosPresets`, added `ChaosStatus` wrapper |
| `flutter_frontend/lib/services/api_service.dart` | Replaced chaos CRUD methods with single `getChaosStatus()` |
| `flutter_frontend/lib/providers/config_provider.dart` | Polls `/api/chaos/status`; exposes `chaosVariation`; write methods removed |
| `flutter_frontend/lib/screens/config_screen.dart` | Presets grid removed; read-only field rows; DevCycle banner + dashboard link |
| `flutter_frontend/lib/widgets/{chaos_preset_buttons,llm_failures_section,latency_injection_section,http_errors_section}.dart` | Deleted |
| `flutter_frontend/pubspec.yaml` | Added `url_launcher: ^6.3.0` |
| `.github/workflows/chaos.yml` | Pending: replace backend curl calls with DevCycle Management API calls; rename presets to dashes |
| `AGENTS.md` | Pending: update endpoint list + chaos description |
