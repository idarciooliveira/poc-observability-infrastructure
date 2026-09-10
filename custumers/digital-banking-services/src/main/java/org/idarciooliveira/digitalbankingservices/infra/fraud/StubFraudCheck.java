package org.idarciooliveira.digitalbankingservices.infra.fraud;

import io.opentelemetry.instrumentation.annotations.WithSpan;
import org.idarciooliveira.digitalbankingservices.domain.usecase.FraudCheck;
import org.idarciooliveira.digitalbankingservices.infra.metrics.TransferMetrics;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.math.BigDecimal;

/**
 * Phase 1 placeholder: replaced by HttpFraudCheck - fraud logic now in fraud-service.
 * Kept as reference/fallback.
 */
public class StubFraudCheck implements FraudCheck {

    private static final Logger log = LoggerFactory.getLogger(StubFraudCheck.class);
    private static final BigDecimal SUSPICIOUS_THRESHOLD = new BigDecimal("10000");

    private final TransferMetrics metrics;

    public StubFraudCheck(TransferMetrics metrics) {
        this.metrics = metrics;
    }

    @WithSpan("fraud.check")
    @Override
    public boolean isApproved(String sourceAccountNumber, BigDecimal amount) {
        long start = System.nanoTime();
        try {
            boolean approved = amount.compareTo(SUSPICIOUS_THRESHOLD) < 0;
            if (approved) {
                log.info("fraud.check status=approved source={} amount={}", sourceAccountNumber, amount);
            } else {
                log.warn("fraud.check status=rejected source={} amount={}", sourceAccountNumber, amount);
                metrics.countFraudRejected();
            }
            return approved;
        } finally {
            metrics.recordFraudDuration(System.nanoTime() - start);
        }
    }
}
