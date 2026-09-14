# Centralized Multi-Tenant Observability POC

A proof of concept for a centralized, multi-tenant observability platform for financial-services applications.

The project simulates three independent client organizations:

- **Client A:** Banking (direct OTLP export to the platform)
- **Client B:** Insurance (direct OTLP export to the platform)
- **Client C:** Retail orders (OTLP to a customer-side collector, which forwards to the platform — Ch.2)

Each client runs its own Spring Boot services inside an isolated Docker network. Applications send telemetry through OpenTelemetry to a shared OTLP endpoint exposed by the centralized observability infrastructure.

The platform collects, processes, stores, and visualizes:

- Metrics
- Logs
- Traces

using the **OpenTelemetry + LGTM** stack.

> This is a POC. It is intended to validate the architecture and operational workflow, not to provide a production-ready platform.

## Quickstart

Prerequisites: Docker (Desktop on Windows/macOS, or Engine on Linux) with `docker compose`.

```powershell
# Windows (PowerShell)
.\scripts\up.ps1
```

```sh
# Linux / macOS / Git Bash
./scripts/up.sh
```

This starts all four stacks in order (observability → banking → insurance → retail-orders),
creating missing `.env` files from `.env.example` on first run. The root
`.env` is the single source of truth for `BANKING_TOKEN`/`INSURANCE_TOKEN`/`RETAIL_TOKEN` —
the scripts export them so gateway and clients always agree (FR-06).

Endpoints: Grafana https://grafana.localhost (served through Traefik; its local certificate may require browser approval; creds from root `.env`: `GF_ADMIN_USER`/`GF_ADMIN_PASSWORD`), Banking API
http://localhost:8080, Insurance API http://localhost:8083, Retail API http://localhost:8084.

```powershell
.\scripts\down.ps1          # stop everything (add -Volumes to drop data)
```

### Ops runbook (local simulation)

- **Config edits need restarts.** `up -d` does not reload mounted files for
  the OTel gateway / internal collector / Loki / Tempo / Mimir — restart the
  container after editing (`docker compose restart otel-gateway`). Traefik's
  file-provider watches and reloads on its own.
- **Fresh `.env` + stale volumes = auth failures.** `.env` files are
  gitignored; a fresh copy from `.env.example` carries placeholder secrets
  that won't match an existing Postgres/Grafana volume (symptom: banking-api
  `password authentication failed`, Grafana 401). Either reuse the previous
  `.env` or reset volumes once (`down -Volumes`, or drop just the banking PG
  volume) and re-run load. Grafana admin can also be reset without wiping
  data: `docker exec -u 0 poc-grafana grafana-cli admin reset-admin-password <pass>`.
- **Prod-like hardening (Ch.2, Gap 5).** Retail services carry `mem_limit` /
  log caps; retention is 7d everywhere (Loki `retention_period`, Tempo
  `block_retention`, Mimir `compactor_blocks_retention_period`); per-tenant
  ingestion limits are explicit (Mimir `ingestion_rate`/`ingestion_burst_size`/
  `max_global_series_per_user`, Loki `ingestion_rate_mb`/`burst`, Traefik
  rate-limit). Re-run `tests/tenant-isolation/spoof-proof.sh` after backend
  changes.

### Generate load

```powershell
.\scripts\load-k6.ps1 -DurationMin 1 -Vus 2                 # quick smoke test (~2.5 min)
.\scripts\load-k6.ps1 -DurationMin 5 -Vus 10                # default load across all three tenants
.\scripts\load-k6.ps1 -DurationMin 5 -Vus 10 -Chaos latency # 2.5s downstream delay (trips 2s timeout)
.\scripts\load-k6.ps1 -DurationMin 5 -Vus 10 -Chaos rejects # 30% forced fraud/risk rejections
# Git Bash: ./scripts/load-k6.sh --duration-min 1 --vus 2 [--chaos off|latency|rejects]
# k6 runs in Docker (grafana/k6, no local install); watch it live in Grafana → Tenant Overview.
```

## Architecture

```text
                               INTERNET
                                   |
                                   |
                     Public OTLP Endpoint (Traefik :443,
                          per-tenant SNI routing)
                                   |
                                   v
                         +---------------------+
                         |   OTEL GATEWAY      |
                         |                     |
                         | Authentication      |
                         | Tenant identification|
                         | Telemetry routing   |
                         +----------+----------+
                                   |
                                   |
                           PRIVATE NETWORK
                                   |
                                   v
                         +---------------------+
                         |  OTEL COLLECTOR     |
                         +----------+----------+
                                   |
                    +--------------+--------------+
                    |              |              |
                    v              v              v
                 +------+       +------+       +------+
                 | Loki |       |Tempo |       |Mimir |
                 | Logs |       |Traces|       |Metric|
                 +------+       +------+       +------+
                    |              |              |
                    +--------------+--------------+
                                   |
                                   v
                              +-----------+
                              |  Grafana  |
                              +-----------+


        CLIENT A                       CLIENT B                       CLIENT C
         BANKING                       INSURANCE                   RETAIL ORDERS

 +-------------------------+  +-------------------------+  +-------------------------+
 | client-banking-network  |  | client-insurance-network|  | client-retail-orders    |
 |                         |  |                         |  |                         |
 | +-------------------+   |  | +-------------------+   |  | +-------------------+   |
 | | Banking API       |   |  | | Insurance API     |   |  | | Retail API        |   |
 | | Spring Boot       |   |  | | Spring Boot       |   |  | | Spring Boot       |   |
 | +--------+----------+   |  | +--------+----------+   |  | +--------+----------+   |
 |          |              |  |          |              |  |          | (OTLP, no   |
 | +--------v----------+   |  | +--------v----------+   |  |          |  auth, LAN  |
 | | Fraud Service     |   |  | | Risk Service      |   |  | +--------v----------+   |
 | +--------+----------+   |  | +--------+----------+   |  | | client-collector  |   |
 |          |              |  |          |              |  | | retail-orders     |   |
 | +--------v----------+   |  | +--------v----------+   |  | +--------+----------+   |
 | | PostgreSQL        |   |  | | PostgreSQL        |   |  |          | (OTLP+TLS+  |
 | +-------------------+   |  | +-------------------+   |  | | PostgreSQL        |   |
 +-------------------------+  +-------------------------+  +-------------------------+
          |                             |                             |
          +------------- direct OTLP via Traefik :443 ----------------+
                                        |
                        retail via local collector -> Traefik :443
                                        |
                                        v
                              PUBLIC OTEL ENDPOINT (Traefik :443)
```

### Network boundary

Clients communicate with the telemetry ingestion endpoint only.

```text
Client A  -----> OTLP Gateway (direct, via Traefik :443)
Client B  -----> OTLP Gateway (direct, via Traefik :443)
Client C  -----> OTLP Gateway (via client-collector-retail-orders, Traefik :443)

Client A  -X-> Client B
Client A  -X-> Client C
Client A  -X-> Loki
Client A  -X-> Tempo
Client A  -X-> Mimir
Client A  -X-> Grafana

Client B  -X-> Client A
Client B  -X-> Client C
Client B  -X-> Loki
Client B  -X-> Tempo
Client B  -X-> Mimir
Client B  -X-> Grafana

Client C app -X-> OTLP Gateway (only its local collector may egress)
Client C  -X-> Client A
Client C  -X-> Client B
Client C  -X-> Loki
Client C  -X-> Tempo
Client C  -X-> Mimir
Client C  -X-> Grafana
```

## Technology Stack

### Client applications

- Java
- Spring Boot
- Spring Web
- Spring Data JPA
- PostgreSQL
- OpenTelemetry Java Agent
- Docker

### Observability

- OpenTelemetry
- OpenTelemetry Collector
- Loki
- Grafana
- Tempo
- Mimir

### Infrastructure

- Docker
- Docker Compose
- Isolated Docker networks
- Public IP
- OTLP/gRPC
- OTLP/HTTP

## Repository Structure

```text
poc-observability-infrastructure/
│
├── custumers/                       # client workloads (isolated networks)
│   ├── digital-banking-services/    # banking-api + postgres (direct OTLP export)
│   ├── fraud-service/               # fraud check used by banking-api
│   ├── insurance-services/          # insurance-api + postgres (direct OTLP export)
│   ├── risk-service/                # risk evaluation used by insurance-api
│   └── retail-orders-services/      # retail-api + client-collector-retail-orders + postgres (Ch.2)
│
├── observability/                   # central platform (private networks)
│   ├── otel/
│   │   ├── gateway-config.yaml      # sole public ingestion: auth + tenant assignment
│   │   └── collector-config.yaml    # internal fan-out with X-Scope-OrgID
│   ├── loki/config.yaml
│   ├── tempo/config.yaml
│   ├── mimir/config.yaml
│   ├── traefik/dynamic/             # edge routes (:443 SNI) + TLS
│   └── grafana/provisioning/        # datasources (federated + per-tenant) + dashboards
│
├── load/poc-load.js                 # k6 banking + insurance + retail scenarios
├── scripts/                         # up/down/load-k6 (.sh + .ps1) + collection/
├── tests/                           # tenant-isolation, collector-failure, security suites
│
├── docker-compose.yml               # platform stack
├── PRD.md
└── README.md
```

## Client Domains

### Banking

The banking client represents a small digital banking platform.

Services:

```text
Banking API
     |
     +---- Fraud Service
     |
     +---- PostgreSQL
```

The Banking API covers:

- Customers
- Accounts
- Transfers
- Transactions
- Balance queries

Main business operation:

```text
POST /transfers
    |
    v
TransferController
    |
    v
TransferService
    |
    +---- Validate account
    |
    +---- Validate balance
    |
    +---- Fraud Service
    |
    +---- Debit source
    |
    +---- Credit destination
    |
    v
PostgreSQL
```

### Insurance

The insurance client represents a small insurance policy management system.

Services:

```text
Insurance API
     |
     +---- Risk Service
     |
     +---- PostgreSQL
```

The Insurance API covers:

- Customers
- Policies
- Claims
- Payments

Main business operation:

```text
POST /policies/{id}/claims
    |
    v
ClaimController
    |
    v
ClaimService
    |
    +---- Validate policy
    |
    +---- Validate coverage
    |
    +---- Risk Service
    |
    +---- Create claim
    |
    v
PostgreSQL
```

### Retail orders (Ch.2)

The retail client represents a small order-processing business. Unlike banking
and insurance, the app exports telemetry only to its local
`client-collector-retail-orders`, which buffers (file-backed queue) and
forwards via Traefik to the central gateway.

Services:

```text
Retail API
     |
     +---- client-collector-retail-orders (OTLP egress, early PII scrub)
     |
     +---- PostgreSQL
```

Main business operations:

```text
POST /orders
GET /orders/{id}
POST /orders/{id}/cancel
```

## Observability Model

Applications use the OpenTelemetry Java Agent for automatic instrumentation. Manual instrumentation is added around important business operations.

Telemetry flows through the centralized platform:

```text
Application → OTLP → OTel Collector → LGTM
```

The LGTM components are:

```text
Logs   → Loki
Traces → Tempo
Metrics → Mimir
UI     → Grafana
```

### Business telemetry

Banking examples:

```text
bank.transfers.total
bank.transfers.success
bank.transfers.failed
bank.transfer.amount
bank.fraud.check.duration
bank.fraud.rejected
```

Insurance examples:

```text
insurance.claims.total
insurance.claims.approved
insurance.claims.rejected
insurance.claim.amount
insurance.risk.evaluation.duration
insurance.high_risk_claims
```

Retail examples:

```text
retail.orders.created
retail.orders.cancelled
retail.orders.failed
retail.order.value
retail.order.processing.duration
```

### Business traces

Banking:

```text
transfer.process
    |
    +-- fraud.check
    |
    +-- database.update
```

Insurance:

```text
claim.evaluate
    |
    +-- risk.evaluate
    |
    +-- database.insert
```

Telemetry must not contain sensitive information such as customer names, account numbers, card numbers, policyholder PII, passwords, or raw financial credentials. Use synthetic IDs for the POC.

## Multi-Tenancy

Every telemetry record must be associated with a client.

```text
tenant.id = banking-client
tenant.id = insurance-client
tenant.id = retail-client
```

Each client uses its own authentication credential:

```text
BANKING_TOKEN
INSURANCE_TOKEN
RETAIL_TOKEN
```

The gateway maps credentials to tenants and prevents a client from arbitrarily changing its tenant identity.

The platform must preserve the distinction:

```text
BANKING telemetry ≠ INSURANCE telemetry ≠ RETAIL telemetry
```

while processing both through the same centralized infrastructure.

## Grafana

Grafana provides the central visualization interface.

Dashboards should cover:

### Infrastructure

- CPU
- Memory
- HTTP requests
- HTTP errors
- Latency
- JVM metrics
- Database metrics

### Banking

- Transfer rate
- Transfer failures
- Fraud rejection rate
- Transfer latency

### Insurance

- Claim rate
- Claim failures
- Risk rejection rate
- Claim processing latency

### Retail (Ch.2)

- Order rate (created / cancelled / failed)
- Cancel ratio
- Order processing latency
- Order value

### Tenant overview

- Client
- Request rate
- Error rate
- Latency
- Service health

## Distributed Tracing

The POC demonstrates traces across services.

Banking:

```text
Client
  |
  v
Banking API
  |
  v
Fraud Service
  |
  v
PostgreSQL
```

Insurance:

```text
Client
  |
  v
Insurance API
  |
  v
Risk Service
  |
  v
PostgreSQL
```

The trace should make it possible to identify where latency or errors occurred.

Example:

```text
POST /transfers                       820ms
|
+-- transfer.process                  800ms
|
+-- fraud.check                       650ms
|
+-- database.update                   100ms
```

## Reference

The project takes conceptual inspiration from:

**vinsguru/opentelemetry-observability**

The reference is useful for understanding the progression from automatic instrumentation to distributed tracing, metrics, logs, sampling, and custom business instrumentation.

## Project Scope

The requirements, validation criteria, implementation phases, failure scenarios, and learning objectives are documented separately in [PRD.md](PRD.md).
