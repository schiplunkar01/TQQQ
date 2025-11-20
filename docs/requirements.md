# TQQQ Agent Requirements

## Purpose & scope
This document specifies an agentic trading assistant that monitors TQQQ, generates buy/hold/sell signals using ML models, sends two‑way SMS confirmations to a human operator, and (on confirmation) executes trades via a broker (paper-mode by default). It covers functional behavior, data & model contracts, security, testing, deployment, and acceptance criteria.

## High-level architecture
- Data ingestion: market data via `yfinance` (or exchange/broker feed).
- Feature pipeline: time-series feature extraction (returns, vol, RSI, date features).
- Inference: classifier (LightGBM/RandomForest) + regime model (LSTM) + SMA200 rule → ensemble vote → signal.
- Human-in-the-loop: send SMS, accept YES/NO reply, require YES to execute.
- Execution: Broker adapter (Alpaca recommended) with `DRY_RUN` safety gates.
- Observability: structured logs, event persistence, dry-run default.

## Actors & user stories
- Operator receives SMS with concise signal and replies YES/NO; YES triggers trade.
- Developer loads models by path; models versioned and auditable.
- SRE receives alerts on failures and can toggle `DRY_RUN`.

## Functional requirements (FR)
FR1 Data ingestion
- FR1.1 Fetch OHLCV (and VIX) for TQQQ (or configured symbol).
- FR1.2 Support mock-data mode (`USE_MOCK_DATA`) for offline runs.

FR2 Feature pipeline
- FR2.1 Produce exact feature set used by scaler/model and persist feature vectors for audit.

FR3 Model inference
- FR3.1 Load classifier (joblib/pickle) and scaler.
- FR3.2 Load LSTM state_dict (PyTorch) and produce regime probabilities.
- FR3.3 Provide mock models when libraries are missing.

FR4 Ensemble & signal
- FR4.1 Combine SMA200 rule + classifier probability + LSTM bull prob (3-vote ensemble).
- FR4.2 Emit human-readable signal and confidence.

FR5 Human confirmation & SMS
- FR5.1 Send outbound SMS (Twilio) with ID and prompt.
- FR5.2 Validate inbound replies (YES/NO). Timeout if no reply.
- FR5.3 Persist SMS messages and confirmations.

FR6 Execution (broker)
- FR6.1 On confirmed YES, call broker adapter to place orders with quantity and risk controls.
- FR6.2 Respect `DRY_RUN` (simulate/trial) by default.
- FR6.3 Support Alpaca paper mode integration.

FR7 Persistence & audit
- FR7.1 Persist raw data, features, model versions, predictions, SMS interactions, confirmations, order receipts.
- FR7.2 Record timestamps and UIDs.

FR8 Management & ops
- FR8.1 Expose health endpoint or CLI smoke check.
- FR8.2 Support scheduled runs (cron/cloud scheduler) and on-demand runs.

## Non-functional requirements (NFR)
- Security: secrets not committed; use environment variables or secrets manager.
- Safety: `DRY_RUN=true` default; require explicit enablement and admin confirmation to enable live trading.
- Reliability: retry/backoff for network calls.
- Observability: structured logs/metrics and alerts for failures.
- Performance: per-symbol run should finish within seconds on a small VM.
- Testability: unit and integration tests; CI gating.

## Data & model contracts
Input market data columns:
- index: date (UTC)
- open, high, low, close, adj_close (float), volume (int)
- optional: vix_close (float)

Feature vector (example; exact ordering must be stable and recorded in metadata):
- ret_1, ret_2, ret_3, ret_5, ret_10, ret_21, ret_63, ret_126, ret_252
- vol_10, vol_21
- rsi_14
- month, day_of_week

Model artifact format:
- Classifier: joblib/pickle exposing predict_proba(X) -> P(bull).
- Scaler: joblib/pickle `StandardScaler`.
- LSTM: PyTorch state_dict (`.pth`) with wrapper exposing predict_proba(seq).
- Model metadata: JSON/YAML including model name, version, training date, feature ordering, thresholds.

Model directory layout:
- `models/`
  - `classifier_v1.pkl`
  - `scaler_v1.pkl`
  - `lstm_v1.pth`
  - `metadata_v1.json`

## Config & environment variables (minimum)
- MODEL_DIR, DRY_RUN, USE_MOCK_DATA
- TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM, OPERATOR_PHONE_NUMBER
- ALPACA_API_KEY, ALPACA_SECRET_KEY, ALPACA_BASE_URL
- SIGNAL_CONFIDENCE_THRESHOLD, SMS_CONFIRMATION_TIMEOUT, LOG_LEVEL
- FEATURE_COLS_FILE (optional)

## Security & secrets
- Use env vars in dev, secret store in CI/prod.
- Prefer API Key SID + Secret for SDKs; rotate keys regularly.
- Enforce HTTPS for webhooks and verify Twilio request signatures.

## Safety rules & operational constraints
- `DRY_RUN=true` by default; require `DRY_RUN=false` + `ENV=production` + admin key/manual confirmation to place live trades.
- Execution guardrails: daily max notional, per-trade min/max, circuit-breakers (stop trading on N consecutive failures or VIX spike).
- Human confirmation required for each trade unless a tightly constrained auto-approve policy exists.

## Messaging contract (Twilio)
Outbound SMS payload:
- "TQQQ signal: <SIGNAL> — Confidence: <n%> — Reply YES to execute, NO to skip. ID:<uid>"

Inbound reply handling:
- Accept YES/NO (case-insensitive); reply with guidance on invalid input.
- Log replies with `prediction_id`, `signature`, `verified`.

Signature verification:
- Validate `X-Twilio-Signature` using the account auth token; reject 403 if invalid.

## Broker contract (Alpaca recommended)
Adapter interface:
- connect(api_key, secret, base_url)
- get_account(), get_positions(symbol)
- place_order(symbol, side, qty, type='market') -> order_id
- cancel_order(order_id), get_order(order_id)
Adapter should support `simulate=True` or paper-mode.

## Logging, monitoring & alerts
- Structured JSON logs include event_id, model_version, feature snapshot, prediction.
- Metrics: predictions/day, SMS sent, confirmations, orders placed, failures.
- Alerts for critical failures and abnormal rates.

## Testing & QA
- Unit tests for feature engineering, model wrappers, SMS parsing, broker adapter mock.
- Integration tests: dry-run end-to-end with generated models and mock Twilio/broker.
- Smoke test: single-day pipeline run and assert outputs.
- CI (GitHub Actions): lint, unit tests, smoke run with `DRY_RUN=true`.

## Deployment & infra
- Containerized image (Docker) with pinned deps.
- Scheduler: cron or cloud scheduler.
- Storage: S3 or Postgres for events and artifacts.
- Secrets: AWS Secrets Manager / GitHub Secrets.
- Deployment: CI → build image → staging → validate → prod.

## Acceptance criteria (concrete)
- AC1: App runs end-to-end in `DRY_RUN` and produces signal without exceptions.
- AC2: SMS sent and operator can reply YES; confirmation is recorded.
- AC3: With `DRY_RUN=false` and admin toggle, broker adapter receives paper order and returns success.
- AC4: Raw data, features, model versions, predictions, confirmations, and order receipts are persisted and retrievable.
- AC5: CI runs unit tests and smoke tests on PRs.

## Mapping to current repo (`tqqq_agent/`)
Files present and coverage:
- `tqqq_agent/app/main.py` — orchestration, DRY_RUN gates, signal composition (FR1, FR2, FR4 partially, FR7 partially)
- `tqqq_agent/app/utils.py` — data fetch and feature engineering (FR1, FR2)
- `tqqq_agent/app/models.py` — model loader & wrapper with mock fallback (FR3)
- `tqqq_agent/app/sms.py` — Twilio client with mock fallback (FR5)
- `tqqq_agent/app/twilio_webhook.py` — inbound webhook + broker trigger (FR5, FR6) with signature verification
- `tqqq_agent/app/broker.py` — Alpaca adapter with mock fallback (FR6)
- `tqqq_agent/app/store.py` — SQLite persistence for predictions/confirmations/orders (FR7)
- `tqqq_agent/generate_models.py` — helper to synthesize test models (testability)
- `tqqq_agent/models/` — generated model artifacts
- `tqqq_agent/tests/test_twilio_utils.py` — Twilio signature tests

Gaps
- Full production-quality broker integration & order risk management.
- Complete persistence schema + efficient queries and archival.
- Additional unit/integration tests and CI pipeline.
- Health endpoint & metrics export.
- Model training pipeline and model registry.
- RBAC and admin UI to toggle `DRY_RUN=false`.

## Prioritized next steps (estimates)
1. Broker adapter (Alpaca) + safe paper execution flow — 1.5 days
2. Twilio two-way SMS + webhook verification — 1.5 days (some done)
3. Persistence (Postgres/S3) and event audit view — 2 days
4. Model metadata and MLOps basics — 1 day
5. CI + smoke tests — 0.5 day
6. Health/monitoring integration — 1 day
Total safe MVP ~7.5 person-days.

## Acceptance test scenarios
- Run pipeline with `USE_MOCK_DATA=true, DRY_RUN=true` → no exceptions, signal logged.
- Send SMS → verify inbound YES triggers saved confirmation and simulated order in DB.
- Attempt live trade with `DRY_RUN=false` and admin toggle → paper order placed (Alpaca) and receipt saved.
- Fail model load → mock fallback runs and pipeline completes with warning.

## Appendix: example `.env`
- MODEL_DIR=./tqqq_agent/models
- DRY_RUN=true
- USE_MOCK_DATA=false
- TWILIO_ACCOUNT_SID=
- TWILIO_AUTH_TOKEN=
- TWILIO_FROM=
- OPERATOR_PHONE_NUMBER=
- ALPACA_API_KEY=
- ALPACA_SECRET_KEY=
- ALPACA_BASE_URL=https://paper-api.alpaca.markets
- SIGNAL_CONFIDENCE_THRESHOLD=0.5
- SMS_CONFIRMATION_TIMEOUT=1800
- LOG_LEVEL=INFO
