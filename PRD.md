# PRD: Centralized Multi-Tenant Observability POC

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
