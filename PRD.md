# PRD: Centralized Multi-Tenant Observability POC

## Development chapters

This PRD is organized in two chapters. Chapter 1 documents the original POC and the architecture it validates. Chapter 2 defines the continuation of that POC, which adds a production-like Docker environment and compares direct telemetry export with customer-side collection.

## Chapter 1: original centralized observability POC

### Starting point

The original POC models a centralized Observability-as-a-Service platform for two independent financial-services customers:

- Banking
- Insurance

Each customer runs Spring Boot services and PostgreSQL in its own Docker network. Applications use the OpenTelemetry Java Agent and send metrics, logs, and traces to a shared OTLP ingestion endpoint owned by the observability platform.

The platform receives telemetry through an OpenTelemetry gateway, identifies the tenant, routes data through an internal collector, and stores it in the LGTM stack:

```text
Customer applications
    -> OTLP gateway
    -> Internal OTel Collector
    -> Mimir, Loki, Tempo
    -> Grafana
```

### Why this chapter exists

The first chapter answers the basic architecture question:

> Can one company operate a shared observability platform for multiple customers while keeping customer networks and telemetry separated?

The POC validates:

- Separate customer Docker networks
- Centralized OTLP ingestion
- Tenant authentication
- Server-side tenant assignment
- Metrics, logs, and distributed traces
- Business-level instrumentation
- Tenant-aware storage routing
- Grafana dashboards
- Failure and latency investigation

The gateway assigns tenant identity from the customer credential and overwrites any tenant value supplied by the application. The internal collector routes each tenant to its own Loki, Tempo, and Mimir tenant context.

The original POC is intentionally not production-ready. It uses Docker Compose, local storage volumes, development credentials, limited edge security, and an operator-focused Grafana deployment. Its purpose is to prove the central collection and multi-tenancy model before adding operational complexity.

### End state of chapter 1

At the end of the original POC, the repository contains two working customer simulations and one central observability stack:

```text
Banking application  -> Central OTLP gateway
Insurance application -> Central OTLP gateway
```

This is the baseline for the continuation. Existing functional requirements remain valid unless Chapter 2 explicitly extends them.

## Chapter 2: production-like Docker continuation

### Objective

The continuation evolves the original POC into a production-like Docker environment and compares two telemetry collection approaches:

1. Direct application export to the central OTLP gateway.
2. Application export to a customer-side collector, which forwards telemetry to the central platform.

The goal is not to claim that Docker Compose is a production platform. The goal is to reproduce the important production boundaries, security controls, failure modes, and onboarding workflow before moving to a larger runtime such as Kubernetes.

### Architecture comparison

The existing customers remain the direct-export baseline:

```text
Banking application
    -> Central OTLP gateway
    -> Internal OTel Collector
    -> LGTM

Insurance application
    -> Central OTLP gateway
    -> Internal OTel Collector
    -> LGTM
```

A third customer is added to validate the customer-side collector model:

```text
Retail orders application
    -> client-collector-retail-orders
    -> Traefik
    -> Central OTLP gateway
    -> Internal OTel Collector
    -> LGTM
```

The central gateway remains authoritative. It must authenticate the customer, assign the tenant, and overwrite tenant attributes received from either the application or the customer-side collector.

### Third customer application

The third customer represents a retail order-processing business. It should remain small, but it must generate realistic business telemetry.

The minimum application scope is:

- `POST /orders`
- `GET /orders/{id}`
- `POST /orders/{id}/cancel`
- Product and quantity validation
- Order total calculation
- Order status changes
- Controlled errors
- Artificial latency for investigation scenarios

The application should produce business telemetry such as:

```text
retail.orders.created
retail.orders.cancelled
retail.orders.failed
retail.order.value
retail.order.processing.duration
```

The customer-side collector must live inside the customer deployment bundle and use the name:

```text
client-collector-retail-orders
```

The application must send telemetry only to this local collector. It must not connect directly to the central gateway.

### Repository organization

The repository should be reorganized so that customer workloads and platform infrastructure are clearly separated. The existing `custumers` directory should be renamed to `customers` as part of the cleanup, with references in scripts and Compose files updated together.

The target structure is:

```text
apps/
  banking/
  insurance/
  retail-orders/

platform/
  otel/
  loki/
  tempo/
  mimir/
  grafana/
  traefik/

customers/
  banking/
  insurance/
  retail-orders/
    retail-api/
    client-collector-retail-orders/
      collector-config.yaml

deploy/compose/
  platform.yml
  banking.yml
  insurance.yml
  retail-orders.yml
  production-like.yml

tests/
  tenant-isolation/
  telemetry-routing/
  collector-failure/
  security/

docs/
  architecture-direct.md
  architecture-client-collector.md
  onboarding-customer.md
  production-readiness.md
```

The existing POC may be moved incrementally. The cleanup must not change tenant behavior or discard existing customer functionality.

### Edge proxy decision

Traefik is the selected edge proxy for the production-like Docker environment.

Traefik is chosen because it provides Docker service discovery, dynamic routing, OTLP/gRPC support, TLS, mTLS, rate-limit middleware, and metrics with less manual configuration than NGINX. Caddy remains a possible option for a simpler HTTPS-only deployment. NGINX remains a possible later choice if the platform needs more manually controlled edge behavior.

Traefik must expose only the public secure endpoint:

```text
443/tcp
```

The OTLP gateway ports must remain private. Traefik handles the edge connection, while the OTLP gateway handles customer authentication and tenant assignment.

### Docker network boundaries

The production-like environment must use explicit network boundaries:

```text
client-banking
client-insurance
client-retail-orders
otel-ingress
observability-internal
```

Applications join only their own customer network. The retail customer-side collector joins its customer network and `otel-ingress`. Traefik and the central gateway join `otel-ingress`. The internal collector and storage services join only `observability-internal`.

Customer applications must not access Loki, Tempo, Mimir, Grafana, or the internal collector directly.

### Production-like controls

The continuation must add the following controls within Docker:

- TLS or mTLS between customer collectors and the platform
- Secret files or Docker secrets instead of committed credentials
- No development fallback tokens in production-like Compose files
- No unnecessary database host port mappings
- Resource limits on all services
- Health and readiness checks
- Collector batching, retry, queue, and backpressure policies
- Per-tenant ingestion limits
- Tenant-specific retention policies
- Persistent storage volumes
- Grafana tenant and folder isolation
- Restricted actuator and diagnostic endpoints
- Gateway and collector self-monitoring

The central collector remains responsible for final PII filtering and tenant routing. The customer-side collector should perform early filtering and buffering, but it must not be trusted as a security boundary.

### Validation plan

The same load and failure scenarios must be executed against the direct-export customers and the retail customer using the local collector.

The POC must compare:

- Telemetry delivery during gateway outage
- Application behavior during WAN or ingress failure
- Collector restart recovery
- CPU and memory usage
- Telemetry loss under overload
- PII filtering before telemetry leaves the customer network
- Customer onboarding effort
- Configuration and operational complexity
- Tenant isolation and spoofing resistance

Required security tests include:

1. Send a banking credential with `tenant.id=insurance-client`.
2. Send a retail credential with `tenant.id=banking-client`.
3. Confirm that the gateway overwrites both values correctly.
4. Attempt to access another customer's Grafana data.
5. Revoke or rotate a customer credential.
6. Confirm that expired credentials cannot ingest telemetry.

Required resilience tests include:

1. Stop the central gateway while generating application traffic.
2. Stop the retail customer-side collector while generating application traffic.
3. Restart the collector and measure recovered telemetry.
4. Restart Loki, Tempo, and Mimir independently.
5. Generate traffic above the configured tenant quota.

### Decision criteria

The client-side collector becomes the default customer deployment model if it provides better results for network outage tolerance, early data protection, buffering, and operational control without creating an unacceptable onboarding burden.

Direct application export may remain available for small customers, development environments, and low-complexity integrations. The central gateway, tenant enforcement, storage isolation, and Grafana authorization are required in both models.

## 1. Product Definition

### 1.1 Problem

Financial-services organizations may operate independent applications and services while relying on a centralized observability platform.

This POC validates how multiple organizations can send telemetry to the same platform while maintaining:

- Tenant identification
- Tenant separation
- Network isolation
- Centralized telemetry collection
- Business-level observability
- Failure and latency investigation

### 1.2 Product Goal

Build a small proof of concept for a centralized, multi-tenant Observability-as-a-Service architecture.

The POC must demonstrate that two independent financial-services clients can use a shared observability platform without gaining direct network access to each other's applications or to the platform's internal storage services.

### 1.3 Scope

The POC contains two simulated clients:

1. Banking
2. Insurance

Each client has:

- Spring Boot services
- PostgreSQL
- Its own isolated Docker network
- OpenTelemetry instrumentation

The centralized platform provides:

- Public OTLP ingestion
- Tenant identification
- Telemetry collection
- Metrics
- Logs
- Distributed traces
- Centralized storage
- Grafana visualization

### 1.4 Non-Goals

The first POC is **not** intended to provide:

- A production-ready platform
- Kubernetes deployment
- Production-grade TLS/mTLS
- Advanced tenant management
- Client-specific Grafana access
- Full alerting
- SLO/SLA management
- LLM observability

These may be considered in later iterations.

---

## 2. Users and Demonstration Roles

### Client A: Banking

Represents a digital banking organization.

Core business operation:

```text
POST /transfers
    |
    +-- account validation
    +-- balance validation
    +-- fraud check
    +-- debit
    +-- credit
```

### Client B: Insurance

Represents an insurance organization.

Core business operation:

```text
POST /policies/{id}/claims
    |
    +-- policy validation
    +-- coverage validation
    +-- risk evaluation
    +-- claim creation
```

### Observability Operator

The operator uses Grafana, metrics, traces, and logs to understand system health and investigate failures.

---

## 3. Functional Requirements

### FR-01: Client Isolation

The system must run Banking and Insurance in separate Docker networks.

```text
client-banking
client-insurance
observability
```

Banking must not directly communicate with Insurance.

Insurance must not directly communicate with Banking.

### FR-02: Observability Isolation

Client networks must not have direct access to:

- Loki
- Tempo
- Mimir
- Grafana

Clients may only reach the telemetry ingestion endpoint.

### FR-03: Shared OTLP Ingestion

Both clients must send telemetry through the same public OTLP endpoint.

Required protocol:

- OTLP/gRPC

Optional:

- OTLP/HTTP

### FR-04: Telemetry Collection

The platform must collect:

- Metrics
- Logs
- Traces

from both clients.

### FR-05: Tenant Identification

Every telemetry record must contain tenant information.

Example:

```text
tenant.id = banking-client
tenant.id = insurance-client
```

### FR-06: Tenant Authentication

Each client must have its own authentication credential.

```text
BANKING_TOKEN
INSURANCE_TOKEN
```

The gateway must map the credential to the corresponding tenant.

A client must not be able to override its tenant identity.

Example of an invalid attempt:

```text
INSURANCE_TOKEN
    +
tenant.id = banking-client
```

This must not allow Insurance to impersonate Banking.

### FR-07: Banking Observability

The platform must expose enough telemetry to observe:

- Transfer rate
- Successful transfers
- Failed transfers
- Fraud rejections
- Transfer latency
- Fraud-check latency

### FR-08: Insurance Observability

The platform must expose enough telemetry to observe:

- Claim rate
- Approved claims
- Rejected claims
- Risk evaluation latency
- Claim processing latency

### FR-09: Distributed Tracing

A Banking transfer must be traceable across:

```text
Banking API
    ↓
Fraud Service
    ↓
PostgreSQL
```

An Insurance claim must be traceable across:

```text
Insurance API
    ↓
Risk Service
    ↓
PostgreSQL
```

### FR-10: Business Instrumentation

Automatic instrumentation must be supplemented with business-level instrumentation.

Banking:

```text
transfer.process
fraud.check
database.update
```

Insurance:

```text
claim.evaluate
risk.evaluate
database.insert
```

### FR-11: Sensitive Data Protection

Telemetry must not contain:

- Customer names
- Account numbers
- Card numbers
- Policyholder PII
- Passwords
- Raw financial credentials

Synthetic IDs must be used for the POC.

### FR-12: Visualization

Grafana must provide dashboards covering:

- Infrastructure
- Banking
- Insurance
- Tenant overview

---

## 4. Failure and Investigation Requirements

The POC must include controlled failure scenarios.

### Banking

- Insufficient balance
- Account not found
- Fraud rejected
- Fraud service timeout
- Database failure
- Artificial latency
- HTTP 500

### Insurance

- Policy not active
- Coverage exceeded
- Invalid claim
- Risk service timeout
- Database failure
- Artificial latency
- HTTP 500

### Investigation Scenario

At least one demonstration must show how an operator moves from detection to diagnosis.

Example:

```text
Transfer latency increases
        |
        v
Metrics
p95 transfer latency = 2.8s
        |
        v
Trace
fraud.check = 2.5s
        |
        v
Logs
"External risk provider timeout"
```

The intended investigation workflow is:

```text
Metrics
   ↓
Detect abnormal behavior

Trace
   ↓
Locate slow or failing component

Logs
   ↓
Understand the failure
```

This relationship between metrics, traces, and logs is a core acceptance criterion.

---

## 5. Acceptance Criteria

The POC is successful when all of the following are demonstrated.

### Client Connectivity

- Banking can send OTLP telemetry.
- Insurance can send OTLP telemetry.
- Both clients use the same public OTLP endpoint.
- OTLP/gRPC works.
- OTLP/HTTP works if implemented.

### Network Isolation

- Banking cannot communicate directly with Insurance.
- Insurance cannot communicate directly with Banking.
- Clients cannot directly access Loki.
- Clients cannot directly access Tempo.
- Clients cannot directly access Mimir.
- Clients cannot directly access Grafana.
- Observability services communicate through their private network.

### Telemetry

- Banking logs arrive.
- Insurance logs arrive.
- Banking metrics arrive.
- Insurance metrics arrive.
- Banking traces arrive.
- Insurance traces arrive.
- Distributed traces work across services.

### Tenant Isolation

- Banking telemetry is identified as Banking.
- Insurance telemetry is identified as Insurance.
- Banking cannot impersonate Insurance.
- Insurance cannot impersonate Banking.
- Grafana can filter telemetry by tenant.

### Failure Scenarios

- Banking fraud failure can be observed.
- Insurance risk failure can be observed.
- Database failures can be observed.
- Artificial latency can be observed.
- HTTP errors can be observed.

---

## 6. Implementation Plan

The project should be implemented incrementally.

### Phase 1 — Banking

Build:

```text
Banking API
+
PostgreSQL
```

Verify the business functionality before adding observability.

### Phase 2 — OpenTelemetry

Add:

```text
OpenTelemetry Java Agent
```

Verify:

```text
Metrics ✓
Logs ✓
Traces ✓
```

### Phase 3 — Observability Infrastructure

Deploy:

```text
OTel Collector
Loki
Tempo
Mimir
Grafana
```

Verify that Banking can send telemetry to the centralized platform.

### Phase 4 — Distributed Tracing

Add:

```text
Fraud Service
```

Verify:

```text
Banking API
    ↓
Fraud Service
    ↓
PostgreSQL
```

appears as a distributed trace.

### Phase 5 — Insurance

Build:

```text
Insurance API
+
Risk Service
+
PostgreSQL
```

Connect it to the same observability infrastructure.

### Phase 6 — Multi-Tenancy

Introduce:

```text
tenant.id
```

and client authentication.

Verify that both clients can use the same OTLP endpoint without mixing telemetry.

### Phase 7 — Network Isolation

Create:

```text
client-banking
client-insurance
observability
```

Verify all isolation rules.

### Phase 8 — Failure Testing

Introduce:

```text
Latency
Errors
Timeouts
Database failures
Service failures
```

Use Grafana to investigate each scenario.

---

## 7. Definition of Done

The POC is complete when this statement is demonstrably true:

> Two independent financial-services clients, running in isolated Docker networks, can send metrics, logs, and distributed traces through a shared public OpenTelemetry endpoint into a private centralized LGTM observability platform, while maintaining tenant separation and preventing direct network access between clients and the internal observability services.

The final demonstration should show:

```text
                     BANKING
                        |
                        | OTLP
                        v
                    PUBLIC IP
                        |
                        v
                  OTEL COLLECTOR
                        |
              +---------+---------+
              |         |         |
             Loki      Tempo     Mimir
              |         |         |
              +---------+---------+
                        |
                     Grafana
                        ^
                        |
              +---------+---------+
                        |
                        | OTLP
                        |
                    INSURANCE
```

And, most importantly:

```text
BANKING telemetry ≠ INSURANCE telemetry
```

while both are processed by the same centralized observability infrastructure.

---

## 8. Learning Objectives

By completing the POC, the implementer should understand:

### OpenTelemetry

How applications generate and export:

- Metrics
- Logs
- Traces

### OTLP

How telemetry moves between systems:

```text
Application → OTLP → Collector
```

### OpenTelemetry Collector

How telemetry is:

```text
Received
Processed
Enriched
Exported
```

### LGTM

How telemetry is stored and queried:

```text
Logs    → Loki
Traces  → Tempo
Metrics → Mimir
UI      → Grafana
```

### Multi-Tenancy

How one observability platform can serve multiple organizations while keeping their telemetry logically separated.

### Network Security

How clients can send telemetry to a centralized platform without gaining network access to internal observability services.

### Distributed Tracing

How a single business operation can be followed across multiple services.

### Business Observability

How telemetry can represent business operations instead of only CPU, memory, and HTTP metrics.

---

## 9. Future Extensions

After the core POC works, possible extensions include:

- Kubernetes
- OTel DaemonSets / Collectors
- TLS / mTLS
- API Gateway
- Client-specific Grafana access
- Advanced tenant management
- Alerting
- SLO / SLA monitoring
- LLM observability

### LLM Observability

A later iteration could monitor:

- Model
- Provider
- Request count
- Latency
- Input tokens
- Output tokens
- Token usage
- Errors
- Timeouts
- Cost
- Tool calls
- Agent traces
- RAG operations

LLM observability should only be added after the core observability platform is working.
