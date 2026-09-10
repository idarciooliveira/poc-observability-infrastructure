package org.idarciooliveira.digitalbankingservices.infra.fraud;

import io.opentelemetry.instrumentation.annotations.WithSpan;
import org.idarciooliveira.digitalbankingservices.domain.usecase.FraudCheck;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.http.client.ClientHttpRequestFactory;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.math.BigDecimal;

/**
 * HTTP client for the external Fraud Service (Phase 4 distributed tracing).
 * Wraps the business span "fraud.check"; HTTP call auto-instrumented by the agent.
 * On error: wraps as RuntimeException for TransferApplicationService's catch-all.
 */
@Component
public class HttpFraudCheck implements FraudCheck {

    private static final Logger log = LoggerFactory.getLogger(HttpFraudCheck.class);

    private final RestClient restClient;
    private final String fraudServiceUrl;

    public HttpFraudCheck(@Value("${fraud.service.url}") String fraudServiceUrl) {
        this.fraudServiceUrl = fraudServiceUrl;
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(2000);
        factory.setReadTimeout(2000);
        this.restClient = RestClient.builder()
                .requestFactory(factory)
                .build();
    }

    @WithSpan("fraud.check")
    @Override
    public boolean isApproved(String sourceAccountNumber, BigDecimal amount) {
        try {
            FraudCheckRequest request = new FraudCheckRequest(sourceAccountNumber, amount);
            FraudCheckResponse response = restClient.post()
                    .uri(fraudServiceUrl + "/fraud-check")
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(request)
                    .retrieve()
                    .body(FraudCheckResponse.class);

            if (response == null) {
                throw new RuntimeException("Fraud service returned null response");
            }
            return response.approved();
        } catch (Exception e) {
            log.error("Fraud check failed for account {}: {}", sourceAccountNumber, e.getMessage());
            throw new RuntimeException("Fraud check service unavailable", e);
        }
    }

    private record FraudCheckRequest(String sourceAccountNumber, BigDecimal amount) {}

    private record FraudCheckResponse(boolean approved) {}
}
