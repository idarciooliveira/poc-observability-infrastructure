# Phase 5: Insurance Client Implementation Plan

## Context

We're implementing Phase 5 of the POC to add a second tenant (Insurance) and validate the multi-tenant observability architecture. The Banking client (Phase 1-4) is complete with:
- Banking API + Fraud Service + PostgreSQL
- OpenTelemetry instrumentation (auto + custom)
- Distributed tracing working end-to-end
- Telemetry flowing to centralized LGTM stack

Phase 5 adds Insurance Client to prove multiple tenants can share the same observability platform (Phase 6 will add true tenant isolation).

## Recommended Approach

### Architecture Decisions

**Directory Structure**: Mirror banking pattern
- `custumers/insurance-services/` - Insurance API (Spring Boot, port 8080)
- `custumers/risk-service/` - Risk evaluation microservice (Spring Boot, port 8082)

**Database**: Separate PostgreSQL container
- Container: `insurance-postgres` on port 5433 (host)
- Database: `insurance_db`
- Rationale: True tenant isolation from day one

**Docker Compose**: Separate compose file per client
- `custumers/insurance-services/docker-compose.yml`
- Contains: insurance-api, risk-service, postgres
- Network: `client-insurance` (will be isolated in Phase 7)

**Risk Logic**: Threshold-based evaluation
```
Reject if:
  - amount > $50,000 (high-value threshold)
  OR
  - amount > 80% of policy coverage limit (exhaustion risk)
Otherwise: APPROVE
```

## Implementation Steps

### Step 1: Risk Service (2-3 hours)
**Copy fraud-service structure, adapt for risk evaluation**

Create `custumers/risk-service/`:
1. Copy `pom.xml` from fraud-service → change artifactId to `risk-service`
2. Copy `Dockerfile` (no changes needed)
3. Create package `org.idarciooliveira.riskservice`
4. Implement:
   - `RiskServiceApplication.java` - Spring Boot main
   - `RiskCheckRequest.java` - record(UUID policyId, BigDecimal claimAmount, BigDecimal coverageLimit)
   - `RiskCheckResponse.java` - record(boolean approved, String reason)
   - `RiskCheckService.java` - @Service + @WithSpan("risk.assessment") with logic:
     ```java
     if (claimAmount > 50000) reject("high_value")
     if (claimAmount > coverageLimit * 0.80) reject("coverage_exhaustion")
     else approve()
     ```
   - `RiskMetrics.java` - @Component with counters (insurance.risk.rejected, insurance.risk.duration)
   - `RiskCheckController.java` - @RestController POST /risk-check
   - `GlobalExceptionHandler.java` - @RestControllerAdvice
5. Create `application.properties`:
   ```properties
   spring.application.name=risk-service
   server.port=8082
   management.endpoints.web.exposure.include=health,info,metrics
   ```

**Pattern source**: `custumers/fraud-service/` (95% copy with rename)

### Step 2: Insurance API - Domain Layer (4-5 hours)
**Pure business logic, no framework dependencies**

Create `custumers/insurance-services/src/main/java/org/idarciooliveira/insuranceservices/domain/`:

1. **Exceptions** (`domain/exception/`):
   - PolicyNotFoundException.java
   - PolicyInactiveException.java
   - CoverageExceededException.java
   - RiskRejectedException.java
   - ClaimNotFoundException.java

2. **Models** (`domain/model/`):
   - `PolicyStatus.java` - enum(ACTIVE, INACTIVE, EXPIRED)
   - `Policy.java` - immutable domain object:
     ```java
     UUID id, String policyNumber, String holderName, 
     PolicyStatus status, BigDecimal coverageLimit, Instant createdAt
     
     Methods: isActive(), canCover(BigDecimal)
     ```
   - `ClaimStatus.java` - enum(APPROVED, REJECTED_POLICY_NOT_FOUND, REJECTED_POLICY_INACTIVE, REJECTED_COVERAGE_EXCEEDED, REJECTED_RISK)
   - `Claim.java` - domain object with factory:
     ```java
     UUID id, UUID policyId, BigDecimal amount, ClaimStatus status, Instant createdAt
     
     Static: Claim.requested(policyId, amount)
     Method: reject(ClaimStatus reason)
     ```

3. **Repositories** (`domain/repository/`):
   - `PolicyRepository.java` - interface
   - `ClaimRepository.java` - interface

4. **Use Cases** (`domain/usecase/`):
   - `RiskEvaluation.java` - interface with isApproved(policyId, amount, coverageLimit)
   - `ProcessClaimUseCase.java` - core orchestration:
     ```java
     1. Validate amount > 0
     2. Fetch policy (throw PolicyNotFoundException if missing)
     3. Check policy.isActive() (throw PolicyInactiveException)
     4. Check policy.canCover(amount) (throw CoverageExceededException)
     5. Call riskEvaluation.isApproved() (throw RiskRejectedException)
     6. Create Claim.requested(), save, return
     ```

**Pattern source**: `custumers/digital-banking-services/src/main/java/org/idarciooliveira/digitalbankingservices/domain/`

### Step 3: Insurance API - Persistence (3-4 hours)
**JPA adapters implementing domain repositories**

Create `custumers/insurance-services/src/main/java/org/idarciooliveira/insuranceservices/infra/persistence/`:

1. **Policy persistence**:
   - `PolicyEntity.java` - @Entity @Table("policies"):
     ```java
     @Id UUID id, String policyNumber (unique), String holderName,
     @Enumerated(STRING) PolicyStatus status, BigDecimal coverageLimit, Instant createdAt
     ```
   - `PolicyJpaRepository.java` - extends JpaRepository<PolicyEntity, UUID>
   - `PolicyRepositoryAdapter.java` - @Repository implements PolicyRepository, @WithSpan("database.update") on save()

2. **Claim persistence**:
   - `ClaimEntity.java` - @Entity @Table("claims"):
     ```java
     @Id UUID id, UUID policyId (FK), BigDecimal amount,
     @Enumerated(STRING) ClaimStatus status, Instant createdAt
     ```
   - `ClaimJpaRepository.java` - extends JpaRepository<ClaimEntity, UUID>
   - `ClaimRepositoryAdapter.java` - @Repository implements ClaimRepository, @WithSpan("database.update") on save()

3. **Seed data** (`resources/data.sql`):
   ```sql
   INSERT INTO policies VALUES
     ('b1c2e8d0-2222-4b3b-8d2b-000000000001', 'INS-2024-001', 'Alice Johnson', 'ACTIVE', 100000.00, NOW()),
     ('b1c2e8d0-2222-4b3b-8d2b-000000000002', 'INS-2024-002', 'Bob Smith', 'ACTIVE', 50000.00, NOW()),
     ('b1c2e8d0-2222-4b3b-8d2b-000000000003', 'INS-2024-003', 'Charlie Brown', 'INACTIVE', 75000.00, NOW());
   ```

**Pattern source**: `custumers/digital-banking-services/src/main/java/org/idarciooliveira/digitalbankingservices/infra/persistence/`

### Step 4: Insurance API - HTTP Layer (3-4 hours)
**REST API with validation**

Create `custumers/insurance-services/src/main/java/org/idarciooliveira/insuranceservices/infra/http/`:

1. **DTOs** (`http/dto/`):
   - `ClaimRequest.java` - record(@NotNull @DecimalMin("0.01") BigDecimal amount)
   - `ClaimResponse.java` - record with static from(Claim):
     ```java
     UUID id, UUID policyId, BigDecimal amount, String status, Instant createdAt
     ```

2. **Controller**:
   - `ClaimController.java` - @RestController @RequestMapping("/policies"):
     ```java
     @PostMapping("/{policyId}/claims")
     ResponseEntity<ClaimResponse> createClaim(@PathVariable UUID policyId, @Valid @RequestBody ClaimRequest)
     → 201 CREATED on success
     ```

3. **Error handling**:
   - `GlobalExceptionHandler.java` - @RestControllerAdvice:
     ```java
     PolicyNotFoundException → 404
     PolicyInactiveException, CoverageExceededException, RiskRejectedException → 422
     IllegalArgumentException → 422
     MethodArgumentNotValidException → 400
     Exception → 500
     ```

**Pattern source**: `custumers/digital-banking-services/src/main/java/org/idarciooliveira/digitalbankingservices/infra/http/`

### Step 5: Insurance API - Risk Integration (1-2 hours)
**HTTP client to risk-service**

Create `custumers/insurance-services/src/main/java/org/idarciooliveira/insuranceservices/infra/risk/`:

1. `HttpRiskEvaluation.java` - @Component implements RiskEvaluation, @WithSpan("risk.check"):
   ```java
   RestClient with 2s timeouts
   URL from @Value("${risk.service.url}")
   POST /risk-check with {policyId, claimAmount, coverageLimit}
   Return response.approved()
   ```

2. `StubRiskEvaluation.java` - @Component @Profile("test") for testing without service

**Pattern source**: `custumers/digital-banking-services/src/main/java/org/idarciooliveira/digitalbankingservices/infra/fraud/HttpFraudCheck.java`

### Step 6: Insurance API - Application Service (2 hours)
**Transaction boundary + observability**

Create `custumers/insurance-services/src/main/java/org/idarciooliveira/insuranceservices/infra/application/`:

1. `ClaimApplicationService.java` - @Service @Transactional @WithSpan("claim.process"):
   ```java
   Wraps ProcessClaimUseCase
   Try: call useCase, count metric(status=success), log info, return
   Catch each exception type:
     - Count metric with specific status tag
     - Log warn/error with context
     - Re-throw for GlobalExceptionHandler
   Finally: record duration metric
   ```

**Pattern source**: `custumers/digital-banking-services/src/main/java/org/idarciooliveira/digitalbankingservices/infra/application/TransferApplicationService.java`

### Step 7: Insurance API - Metrics (1 hour)
**Custom business metrics**

Create `custumers/insurance-services/src/main/java/org/idarciooliveira/insuranceservices/infra/metrics/`:

1. `ClaimMetrics.java` - @Component:
   ```java
   Counter: insurance.claims.total (tagged by status: success, policy_not_found, policy_inactive, coverage_exceeded, risk_rejected)
   Timer: insurance.claim.duration
   ```

**Pattern source**: `custumers/digital-banking-services/src/main/java/org/idarciooliveira/digitalbankingservices/infra/metrics/TransferMetrics.java`

### Step 8: Insurance API - Configuration (1 hour)

1. `InsuranceServicesApplication.java` - @SpringBootApplication main class

2. `UseCaseConfig.java` - @Configuration with @Bean methods:
   ```java
   @Bean ProcessClaimUseCase(PolicyRepository, ClaimRepository, RiskEvaluation)
   ```

3. `application.properties`:
   ```properties
   spring.application.name=insurance-services
   spring.datasource.url=${SPRING_DATASOURCE_URL:jdbc:postgresql://localhost:5433/insurance_db}
   spring.datasource.username=${SPRING_DATASOURCE_USERNAME:insurance_user}
   spring.datasource.password=${SPRING_DATASOURCE_PASSWORD:insurance_pass}
   spring.jpa.hibernate.ddl-auto=update
   spring.jpa.defer-datasource-initialization=true
   spring.sql.init.mode=always
   
   risk.service.url=${RISK_SERVICE_URL:http://risk-service:8082}
   
   management.endpoints.web.exposure.include=health,info,metrics
   ```

4. Copy `pom.xml` from banking, change artifactId to `insurance-services`

5. Copy `Dockerfile` from banking (no changes)

**Pattern source**: `custumers/digital-banking-services/`

### Step 9: Docker Compose (2-3 hours)

Create `custumers/insurance-services/docker-compose.yml`:

```yaml
services:
  risk-service:
    build: ../risk-service
    container_name: insurance-risk-service
    ports: ["8082:8082"]
    networks: [client-insurance]
    environment:
      OTEL_SERVICE_NAME: risk-service
      OTEL_RESOURCE_ATTRIBUTES: service.namespace=insurance,tenant.id=insurance-client,deployment.environment=dev
      OTEL_TRACES_EXPORTER: otlp
      OTEL_METRICS_EXPORTER: otlp
      OTEL_LOGS_EXPORTER: otlp
      OTEL_METRIC_EXPORT_INTERVAL: 15000
      OTEL_EXPORTER_OTLP_ENDPOINT: http://host.docker.internal:4317
      OTEL_EXPORTER_OTLP_PROTOCOL: grpc
      OTEL_INSTRUMENTATION_MICROMETER_ENABLED: "true"

  insurance-api:
    build: .
    container_name: insurance-api
    ports: ["8080:8080"]
    depends_on:
      postgres: {condition: service_healthy}
      risk-service: {condition: service_started}
    networks: [client-insurance]
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/insurance_db
      SPRING_DATASOURCE_USERNAME: insurance_user
      SPRING_DATASOURCE_PASSWORD: insurance_pass
      RISK_SERVICE_URL: http://risk-service:8082
      OTEL_SERVICE_NAME: insurance-api
      OTEL_RESOURCE_ATTRIBUTES: service.namespace=insurance,tenant.id=insurance-client,deployment.environment=dev
      OTEL_TRACES_EXPORTER: otlp
      OTEL_METRICS_EXPORTER: otlp
      OTEL_LOGS_EXPORTER: otlp
      OTEL_METRIC_EXPORT_INTERVAL: 15000
      OTEL_EXPORTER_OTLP_ENDPOINT: http://host.docker.internal:4317
      OTEL_EXPORTER_OTLP_PROTOCOL: grpc
      OTEL_INSTRUMENTATION_MICROMETER_ENABLED: "true"

  postgres:
    image: postgres:16-alpine
    container_name: insurance-postgres
    ports: ["5433:5432"]
    environment:
      POSTGRES_DB: insurance_db
      POSTGRES_USER: insurance_user
      POSTGRES_PASSWORD: insurance_pass
    volumes: [insurance-postgres-data:/var/lib/postgresql/data]
    networks: [client-insurance]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U insurance_user -d insurance_db"]
      interval: 5s
      timeout: 5s
      retries: 10

volumes:
  insurance-postgres-data:

networks:
  client-insurance:
    name: client-insurance
```

**Pattern source**: `custumers/digital-banking-services/docker-compose.yml`

### Step 10: Build & Verify (3-4 hours)

1. **Build services**:
   ```bash
   cd custumers/risk-service && mvn clean package
   cd custumers/insurance-services && mvn clean package
   ```

2. **Start observability stack** (if not running):
   ```bash
   docker-compose -f docker-compose.yml up -d
   ```

3. **Start insurance services**:
   ```bash
   cd custumers/insurance-services
   docker-compose up -d
   docker-compose logs -f
   ```

4. **Health checks**:
   ```bash
   curl http://localhost:8080/actuator/health  # insurance-api
   curl http://localhost:8082/actuator/health  # risk-service
   ```

5. **Test scenarios**:

   **Successful claim**:
   ```bash
   curl -X POST http://localhost:8080/policies/b1c2e8d0-2222-4b3b-8d2b-000000000001/claims \
     -H "Content-Type: application/json" \
     -d '{"amount": 25000.00}'
   # Expected: 201 Created
   ```

   **Rejected - high value**:
   ```bash
   curl -X POST http://localhost:8080/policies/b1c2e8d0-2222-4b3b-8d2b-000000000001/claims \
     -H "Content-Type: application/json" \
     -d '{"amount": 60000.00}'
   # Expected: 422 Unprocessable Entity
   ```

   **Rejected - coverage exhaustion**:
   ```bash
   curl -X POST http://localhost:8080/policies/b1c2e8d0-2222-4b3b-8d2b-000000000002/claims \
     -H "Content-Type: application/json" \
     -d '{"amount": 45000.00}'
   # Expected: 422 (45k > 80% of 50k coverage)
   ```

   **Rejected - inactive policy**:
   ```bash
   curl -X POST http://localhost:8080/policies/b1c2e8d0-2222-4b3b-8d2b-000000000003/claims \
     -H "Content-Type: application/json" \
     -d '{"amount": 10000.00}'
   # Expected: 422 Unprocessable Entity
   ```

6. **Verify observability in Grafana** (http://localhost:3000):

   **Traces (Tempo)**:
   - Search service: `insurance-api`
   - Verify span hierarchy: `claim.process` → `risk.check` → `risk.assessment` → `database.update`

   **Metrics (Mimir)**:
   ```promql
   rate(insurance_claims_total[5m])
   rate(insurance_risk_rejected[5m])
   histogram_quantile(0.95, rate(insurance_claim_duration_bucket[5m]))
   ```

   **Logs (Loki)**:
   ```logql
   {service_name="insurance-api"} |= "claim.process"
   {service_name="risk-service"} |= "risk.assessment"
   {tenant_id="insurance-client"}
   ```

7. **Verify both tenants visible**:
   - Banking telemetry: `{tenant_id="banking-client"}`
   - Insurance telemetry: `{tenant_id="insurance-client"}`
   - Both flowing to same Tempo/Mimir/Loki

## Success Criteria

- [ ] Insurance API responds on port 8080
- [ ] Risk Service responds on port 8082
- [ ] Database has 3 seed policies
- [ ] Successful claim creates row in claims table
- [ ] All rejection scenarios return correct HTTP status
- [ ] Distributed trace spans in Grafana Tempo: claim.process → risk.check → risk.assessment
- [ ] Custom metrics visible in Grafana Mimir: insurance.claims.total, insurance.risk.rejected
- [ ] Structured logs visible in Grafana Loki with tenant.id=insurance-client
- [ ] Both Banking and Insurance telemetry coexist in observability platform (not yet separated by tenant)

## Files to Create

**Risk Service** (~7 files):
- custumers/risk-service/pom.xml
- custumers/risk-service/Dockerfile
- custumers/risk-service/src/main/java/org/idarciooliveira/riskservice/RiskServiceApplication.java
- custumers/risk-service/src/main/java/org/idarciooliveira/riskservice/RiskCheckService.java
- custumers/risk-service/src/main/java/org/idarciooliveira/riskservice/RiskCheckController.java
- custumers/risk-service/src/main/java/org/idarciooliveira/riskservice/RiskMetrics.java
- custumers/risk-service/src/main/resources/application.properties

**Insurance API** (~30 files):
- custumers/insurance-services/pom.xml
- custumers/insurance-services/Dockerfile
- custumers/insurance-services/docker-compose.yml
- Domain layer: 11 files (models, exceptions, repositories, use cases)
- Infrastructure: 16 files (persistence, HTTP, metrics, risk integration, config)
- Resources: 2 files (application.properties, data.sql)

**Total**: ~40 files, 85% reusable from existing banking patterns

## Key Reusable Patterns

- **ProcessTransferUseCase** → ProcessClaimUseCase (orchestration logic)
- **TransferApplicationService** → ClaimApplicationService (@Transactional + @WithSpan wrapper)
- **HttpFraudCheck** → HttpRiskEvaluation (RestClient integration)
- **TransferMetrics** → ClaimMetrics (Micrometer counters/timers)
- **FraudCheckService** → RiskCheckService (threshold-based logic)
- **Dockerfiles** → Copy verbatim (multi-stage + OTel agent)
- **docker-compose.yml** → Adapt with insurance-specific names

## Estimated Effort

**Total**: 22-30 hours of focused implementation

**Breakdown**:
- Risk Service: 2-3h (simple copy from fraud-service)
- Domain layer: 4-5h (business logic)
- Infrastructure: 10-12h (persistence, HTTP, integration, metrics)
- Configuration: 2-3h (Spring wiring, properties, Docker)
- Testing: 3-4h (scenarios + observability verification)
