# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PulseCheck is a real-time URL health monitoring service. It continuously checks a list of URLs/APIs and alerts when they go down or degrade. The project is built in four weekly phases.

## Architecture

Three distinct services communicate over a shared SQLite file:

```
Flask Dashboard  ──►  SQLite  ◄──  FastAPI Monitor Service
                                           │
                                  Prometheus metrics endpoint
                                           │
                                      Grafana dashboards
                                           │
                                 FastAPI Alert Service (in-app only)
```

- **Flask Dashboard** (`dashboard/`) — user-facing web UI. Add/remove monitored URLs, view live status table, browse incident history. No authentication.
- **FastAPI Monitor Service** (`monitor/`) — async background workers using `httpx` + `asyncio`. Performs HTTP/HTTPS checks on a single global interval, writes results to DB, exposes `/metrics` for Prometheus.
- **FastAPI Alert Service** (`alerter/`) — consumes check results, surfaces active/resolved alerts in-app only. No external notifications (no email, Slack, or webhooks).
- **Prometheus + Grafana** (`infra/`) — scrapes `/metrics`, stores time-series, drives dashboards and on-call alerting rules.
- **Jenkins** (`Jenkinsfile`) — CI pipeline: test → lint → build Docker images → deploy via docker-compose. Also runs a scheduled synthetic check job hourly.

## Key Metrics (Prometheus)

| Metric | Type | Description |
|---|---|---|
| `url_up` | Gauge | 1 = reachable, 0 = down |
| `url_response_time_seconds` | Histogram | End-to-end latency per URL |
| `url_check_total` | Counter | Total checks performed |

SLO target: each URL must respond in under 500 ms, 99% of the time.

## HTTP/HTTPS Check Behavior

Each check sends a `GET` request to the URL and records four data points:

| Field | Description |
|---|---|
| **Reachability** | Did we get any response, or did the connection time out / refuse? |
| **Status code** | Raw HTTP response code (200, 404, 500, etc.) |
| **Response time (ms)** | Time from request sent to first byte of response received |
| **`is_up`** | `True` if status `< 400` and responded within timeout; `False` otherwise |

**Rules:**
- Redirects are followed automatically (3xx is not treated as down)
- `is_up = False` on: 4xx, 5xx, connection refused, or timeout
- One global check interval applies to all URLs (no per-URL intervals)

**Deferred for later:** SSL certificate expiry checks, response body keyword matching, TCP port checks.

## Confirmed Decisions

| Decision | Choice |
|---|---|
| Deployment | Local docker-compose only |
| Authentication | None |
| Database | SQLite throughout (no Postgres migration) |
| Check interval | Single global interval for all URLs |
| Check type | HTTP/HTTPS only |
| Alert notifications | In-app only — written to DB, surfaced in UI |

## Build Phases

### Phase 1 — Flask Dashboard + SQLite

**1.1 Project Scaffolding**
- [✅] Create folder structure: `dashboard/`, `monitor/`, `alerter/`, `infra/`
- [✅] Set up `venv`, `requirements.txt` per service
- [✅] Add root `docker-compose.yml` skeleton (services defined, not yet wired)
- [✅] Add `.env.example` for environment variables

**1.2 Database Schema**
- [ ] `urls` table: `id`, `name`, `url`, `created_at`
- [ ] `checks` table: `id`, `url_id`, `checked_at`, `status_code`, `response_time_ms`, `is_up`
- [ ] `incidents` table: `id`, `url_id`, `started_at`, `resolved_at`, `duration_seconds`, `alert_fired_at`, `alert_resolved_at`
- [ ] Write `schema.sql` + `db.py` helper (connection, migrations)

**1.3 Flask Routes**
- [ ] `GET /` — status table (all URLs + latest check result)
- [ ] `POST /urls` — add a new URL to monitor
- [ ] `DELETE /urls/<id>` — remove a URL
- [ ] `GET /urls/<id>/history` — paginated check history for one URL
- [ ] `GET /incidents` — incident log across all URLs

**1.4 Jinja2 Templates + Static Assets**
- [ ] Base layout with nav
- [ ] Status table: color-coded rows (green/red), last checked time, response time
- [ ] Add-URL form with validation feedback
- [ ] Incident history table

**1.5 Seed Data + Manual Testing**
- [ ] Seed script with 3–5 example URLs
- [ ] Confirm all routes work end-to-end with SQLite

---

### Phase 2 — FastAPI Monitor Service

**2.1 Service Scaffold**
- [ ] FastAPI app with `lifespan` context manager to start/stop background tasks
- [ ] `httpx.AsyncClient` configured with timeouts (connect: 5s, read: 10s)
- [ ] Health check endpoint: `GET /health`

**2.2 Async Check Workers**
- [ ] `CheckWorker` class: takes a URL record, runs `httpx.get`, records result
- [ ] `Scheduler` that launches one worker coroutine per monitored URL on the global interval
- [ ] Graceful shutdown: cancel all worker tasks on SIGTERM

**2.3 Shared Database Write**
- [ ] Write check results to the same SQLite DB the Flask dashboard reads
- [ ] Use `aiosqlite` to avoid blocking the event loop
- [ ] Incident detection logic: open incident on first failure, close on first success after failure

**2.4 Monitor REST Endpoints**
- [ ] `GET /status` — current up/down state for all URLs
- [ ] `GET /urls/{id}/checks?limit=100` — recent check history

**2.5 Docker + docker-compose Integration**
- [ ] Dockerize Monitor Service
- [ ] Wire into `docker-compose.yml` alongside the Flask container
- [ ] Shared volume for SQLite file

---

### Phase 3 — Prometheus + Grafana

**3.1 Prometheus Metrics in Monitor Service**
- [ ] Add `prometheus-client` library
- [ ] Expose `GET /metrics` (Prometheus text format)
- [ ] Instrument three metrics: `url_up`, `url_response_time_seconds`, `url_check_total`
- [ ] Label all metrics with `url` and `url_name`

**3.2 Prometheus Configuration**
- [ ] `infra/prometheus.yml` scrape config targeting Monitor Service `/metrics`
- [ ] 15s scrape interval
- [ ] Add Prometheus container to `docker-compose.yml`

**3.3 Grafana Dashboards**
- [ ] Provision Grafana via `infra/grafana/provisioning/` (datasource + dashboard JSON)
- [ ] Per-URL dashboard panels: uptime %, response time over time, check count
- [ ] Summary dashboard: all URLs side-by-side, sorted by uptime %

**3.4 Alerting Rules**
- [ ] Prometheus alert rule: `url_up == 0` sustained for > 2 minutes → fires `URLDown` alert
- [ ] Second rule: `p99 response time > 500ms` over 5-minute window → fires `URLSlow` alert
- [ ] Alertmanager config: routes alerts to the Alert Service webhook

---

### Phase 4 — Alert Service + Jenkins

**4.1 FastAPI Alert Service Scaffold**
- [ ] Receives `POST /webhook` from Alertmanager (Alertmanager webhook receiver format)
- [ ] Parses alert payload: `alertname`, `labels.url`, `status` (firing / resolved)
- [ ] `GET /alerts` — list of active and recently resolved alerts

**4.2 In-App Alert Tracking**
- [ ] Write firing/resolved alerts to DB with timestamp and affected URL
- [ ] Deduplication: don't create duplicate alert records if same alert is still firing

**4.3 Incident Linkback**
- [ ] On alert fire, look up the open incident in DB and set `alert_fired_at`
- [ ] On resolve, set `alert_resolved_at` on the incident row

**4.4 Jenkinsfile — CI/CD Pipeline**
- [ ] Stage 1 `test`: `pytest` for all three services in parallel
- [ ] Stage 2 `lint`: `ruff check .`
- [ ] Stage 3 `build`: `docker build` for each service, tag with git SHA
- [ ] Stage 4 `deploy`: `docker-compose up -d --build` on the target host

**4.5 Jenkins Scheduled Synthetic Check**
- [ ] Separate Jenkins job (cron: `H * * * *` — every hour)
- [ ] Hits a known-good URL from outside the monitoring stack
- [ ] Fails the job if response time > 1s or status != 200
- [ ] Demonstrates Jenkins beyond pure CI (operational synthetic testing)

## Running the Stack

Commands will be added here as each service is scaffolded. Expected entrypoints:

```bash
# Local development (docker-compose)
docker-compose up --build

# Run a single service in dev mode
cd dashboard && flask run
cd monitor  && uvicorn main:app --reload
cd alerter  && uvicorn main:app --reload

# Tests
pytest dashboard/tests/
pytest monitor/tests/
pytest alerter/tests/

# Lint
ruff check .
```

## Deferred Features (can add later)

- SSL certificate expiry checking
- Response body keyword matching
- TCP port checks
- Per-URL check intervals
- External alert notifications (email / Slack / webhook)
- Dashboard authentication
