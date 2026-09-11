# Centralized Multi-Tenant Observability POC

A proof of concept for a centralized, multi-tenant observability platform for financial-services applications.

The project simulates two independent client organizations:

- **Client A:** Banking
- **Client B:** Insurance

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

This starts all three stacks in order (observability → banking → insurance),
creating missing `.env` files from `.env.example` on first run. The root
`.env` is the single source of truth for `BANKING_TOKEN`/`INSURANCE_TOKEN` —
the scripts export them so gateway and clients always agree (FR-06).

Endpoints: Grafana http://localhost:3000 (creds from root `.env`: `GF_ADMIN_USER`/`GF_ADMIN_PASSWORD`), Banking API
http://localhost:8080, Insurance API http://localhost:8083.

```powershell
.\scripts\down.ps1          # stop everything (add -Volumes to drop data)
```

### Generate load

```powershell
.\scripts\load-k6.ps1 -DurationMin 1 -Vus 2                 # quick smoke test (~2.5 min)
.\scripts\load-k6.ps1 -DurationMin 5 -Vus 10                # default: ~8-10k requests, both tenants
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
                          Public OTLP Endpoint
                               :4317/:4318
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


        CLIENT A                                      CLIENT B
         BANKING                                      INSURANCE

 +-------------------------+              +-------------------------+
 | client-banking-network  |              | client-insurance-network|
 |                         |              |                         |
 | +-------------------+   |              | +-------------------+   |
 | | Banking API       |   |              | | Insurance API     |   |
 | | Spring Boot       |   |              | | Spring Boot       |   |
 | +--------+----------+   |              | +--------+----------+   |
 |          |              |              |          |              |
 | +--------v----------+   |              | +--------v----------+   |
 | | Fraud Service     |   |              | | Risk Service      |   |
 | +--------+----------+   |              | +--------+----------+   |
 |          |              |              |          |              |
 | +--------v----------+   |              | +--------v----------+   |
 | | PostgreSQL        |   |              | | PostgreSQL        |   |
 | +-------------------+   |              | +-------------------+   |
 +-------------+-----------+              +-------------+-----------+
               |                                        |
               +---------------- OTLP -------------------+
                                  |
                                  v
                           PUBLIC OTEL ENDPOINT
```

### Network boundary

Clients communicate with the telemetry ingestion endpoint only.

```text
Client A  -----> OTLP Gateway
Client B  -----> OTLP Gateway

Client A  -X-> Client B
Client A  -X-> Loki
Client A  -X-> Tempo
Client A  -X-> Mimir
Client A  -X-> Grafana

Client B  -X-> Client A
Client B  -X-> Loki
Client B  -X-> Tempo
Client B  -X-> Mimir
Client B  -X-> Grafana
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
observability-poc/
│
├── clients/
│   │
│   ├── banking/
│   │   ├── banking-api/
│   │   │   ├── src/
│   │   │   ├── pom.xml
│   │   │   └── Dockerfile
│   │   │
│   │   └── fraud-service/
│   │       ├── src/
│   │       ├── pom.xml
│   │       └── Dockerfile
│   │
│   └── insurance/
│       ├── insurance-api/
│       │   ├── src/
│       │   ├── pom.xml
│       │   └── Dockerfile
│       │
│       └── risk-service/
│           ├── src/
│           ├── pom.xml
│           └── Dockerfile
│
├── observability/
│   ├── otel/
│   │   └── collector-config.yaml
│   ├── loki/
│   │   └── config.yaml
│   ├── tempo/
│   │   └── config.yaml
│   ├── mimir/
│   │   └── config.yaml
│   └── grafana/
│       └── provisioning/
│
├── docker-compose.yml
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
```

Each client uses its own authentication credential:

```text
BANKING_TOKEN
INSURANCE_TOKEN
```

The gateway maps credentials to tenants and prevents a client from arbitrarily changing its tenant identity.

The platform must preserve the distinction:

```text
BANKING telemetry ≠ INSURANCE telemetry
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
