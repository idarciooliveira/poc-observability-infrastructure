# Architecture — Centralized Multi-Tenant Observability POC

> Source of truth: `README.md`, `PRD.md`, `docker-compose.yml`, `observability/otel/*.yaml`, `observability/traefik/dynamic/routes.yml`.
> Render this file on GitHub / IntelliJ / VS Code (Mermaid supported).

## 1. Overall system

```mermaid
flowchart TB
    subgraph ClientA["CLIENT A — Banking<br/>net: client-banking"]
        BA["Banking API<br/>Spring Boot :8080"]
        FS["Fraud Service"]
        BPG[("PostgreSQL<br/>banking")]
        BA --> FS
        BA --> BPG
        FS --> BPG
    end

    subgraph ClientB["CLIENT B — Insurance<br/>net: client-insurance"]
        IA["Insurance API<br/>Spring Boot :8083"]
        RS["Risk Service"]
        IPG[("PostgreSQL<br/>insurance")]
        IA --> RS
        IA --> IPG
        RS --> IPG
    end

    subgraph ClientC["CLIENT C — Retail Orders (Ch.2)<br/>net: client-retail-orders"]
        RA["Retail API<br/>Spring Boot :8084"]
        CC["client-collector-retail-orders<br/>OTLP egress, PII scrub, file queue"]
        RPG[("PostgreSQL<br/>retail")]
        RA -->|"OTLP, no auth, LAN only"| CC
        RA --> RPG
        CC --> RPG
    end

    subgraph Edge["Edge — otel-ingress"]
        TR["Traefik v3.5 :443<br/>SNI routing + TLS<br/>only public endpoint"]
    end

    subgraph Platform["Platform — observability-internal"]
        GW["OTEL Gateway<br/>auth + tenant upsert<br/>:4317/:4318 banking<br/>:4320/:4321 insurance<br/>:4322/:4323 retail"]
        OC["OTEL Collector<br/>batch / retry / fan-out<br/>X-Scope-OrgID"]
        LK[("Loki<br/>logs")]
        TP[("Tempo<br/>traces")]
        MM[("Mimir<br/>metrics")]
        GR["Grafana 12.1.0<br/>grafana.localhost"]
        GW --> OC
        OC --> LK
        OC --> TP
        OC --> MM
        LK --> GR
        TP --> GR
        MM --> GR
    end

    BA -->|"OTLP/gRPC+HTTP<br/>BANKING_TOKEN<br/>via banking-otlp.localhost"| TR
    IA -->|"OTLP/gRPC+HTTP<br/>INSURANCE_TOKEN<br/>via insurance-otlp.localhost"| TR
    CC -->|"OTLP+TLS<br/>RETAIL_TOKEN<br/>via retail-otlp.localhost"| TR
    TR --> GW
    TR -->|"HTTPS<br/>operator UI"| GR

    style TR fill:#ff9f43,stroke:#333
    style GW fill:#54a0ff,stroke:#333
    style OC fill:#54a0ff,stroke:#333
```

## 2. Ingestion detail (ports, SNI, tokens)

```mermaid
flowchart LR
    subgraph Direct["Direct export (A + B)"]
        A1["Banking API<br/>OTLP exporter"] -->|":443<br/>Host: banking-otlp.localhost<br/>Authorization: BANKING_TOKEN"| T1["Traefik"]
        B1["Insurance API<br/>OTLP exporter"] -->|":443<br/>Host: insurance-otlp.localhost<br/>Authorization: INSURANCE_TOKEN"| T1
    end

    subgraph Buffered["Buffered export (C)"]
        C1["Retail API"] -->|"OTLP :4317 LAN<br/>no token"| C2["client-collector"]
        C2 -->|":443<br/>Host: retail-otlp.localhost<br/>Authorization: RETAIL_TOKEN<br/>TLS + retry + file queue"| T1
    end

    T1 --> G1["Gateway :4317/:4318<br/>banking-client"]
    T1 --> G2["Gateway :4320/:4321<br/>insurance-client"]
    T1 --> G3["Gateway :4322/:4323<br/>retail-client"]
    G1 --> IC["Internal collector"]
    G2 --> IC
    G3 --> IC

    IC -->|X-Scope-OrgID: banking-client| LGTM["Loki / Tempo / Mimir"]
    IC -->|X-Scope-OrgID: insurance-client| LGTM
    IC -->|X-Scope-OrgID: retail-client| LGTM
```

Gateway is authoritative: it maps credential → tenant and **overwrites** any `tenant.id` sent by the app or client-collector (FR-06, spoof-proof — see `tests/tenant-isolation/spoof-proof.sh`).

## 3. Network boundaries

```mermaid
flowchart TB
    subgraph N1["client-banking"]
        n1a["banking-api<br/>fraud-service<br/>postgres"]
    end
    subgraph N2["client-insurance"]
        n2a["insurance-api<br/>risk-service<br/>postgres"]
    end
    subgraph N3["client-retail-orders"]
        n3a["retail-api<br/>postgres"]
        n3b["client-collector<br/>(also in otel-ingress)"]
    end
    subgraph N4["otel-ingress"]
        n4a["traefik"]
        n4b["otel-gateway (egress side)"]
        n3b
    end
    subgraph N5["observability-internal"]
        n5a["traefik<br/>gateway<br/>collector<br/>loki / tempo / mimir<br/>grafana"]
    end

    N1 -.->|"OTLP via Traefik :443 only"| N4
    N2 -.->|"OTLP via Traefik :443 only"| N4
    n3a -.->|"LAN OTLP to local collector only"| n3b
    N4 --> N5
```

Denied (enforced by Compose networks, no host ports on backends):

* Client A ✕ Client B/C, ✕ Loki/Tempo/Mimir/Grafana/internal-collector
* Client C app ✕ gateway directly (only its local collector may egress)
* Gateway OTLP ports (`4317/4318, 4320/4321, 4322/4323`) on `observability-internal` only

## 4. Telemetry flow (Metrics → Trace → Logs)

```mermaid
sequenceDiagram
    participant App as Banking/Insurance/Retail API
    participant Side as client-collector (retail only)
    participant Edge as Traefik :443
    participant GW as OTel Gateway
    participant IC as OTel Collector
    participant LTM as Loki / Tempo / Mimir
    participant Graf as Grafana

    App->>App: business op + auto instrumentation<br/>(transfer.process / claim.evaluate / orders)
    alt retail
        App->>Side: OTLP (LAN)
        Side->>Side: early PII scrub + batch + file queue
        Side->>Edge: OTLP+TLS + RETAIL_TOKEN
    else banking / insurance
        App->>Edge: OTLP + BANKING/INSURANCE_TOKEN
    end
    Edge->>GW: route by SNI Host
    GW->>GW: authenticate token → assign tenant.id (overwrite)
    GW->>IC: OTLP (private net)
    IC->>IC: final PII filter + batch + X-Scope-OrgID routing
    IC->>LTM: export per-tenant
    Graf->>LTM: query (federated + per-tenant datasources)
```

Investigation path: Grafana Tenant Overview → p95 latency spike (Mimir) → exemplar trace (Tempo, e.g. `fraud.check = 2.5s`) → correlated logs (Loki, e.g. `External risk provider timeout`).

## 5. Compose layout

| File | Stack | Networks |
|---|---|---|
| `docker-compose.yml` | traefik, otel-gateway, otel-collector, loki, tempo, mimir, grafana | `otel-ingress`, `observability-internal` |
| `custumers/digital-banking-services/` + `fraud-service/` | banking-api, fraud, postgres | `client-banking-network` |
| `custumers/insurance-services/` + `risk-service/` | insurance-api, risk, postgres | `client-insurance-network` |
| `custumers/retail-orders-services/` | retail-api, client-collector-retail-orders, postgres | `client-retail-orders` (+ `otel-ingress` for collector only) |

Ops: `./scripts/up.sh` → `./scripts/load-k6.sh --duration-min 5 --vus 10` (k6 in Docker, no local install) → Grafana Tenant Overview. Config edits need container restart (except Traefik file provider). See `README.md` Ops runbook.
