package org.idarciooliveira.digitalbankingservices.infra.fraud;

import io.opentelemetry.instrumentation.annotations.WithSpan;
import org.idarciooliveira.digitalbankingservices.domain.usecase.FraudCheck;
import org.idarciooliveira.digitalbankingservices.infra.metrics.TransferMetrics;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;

/**
 * Phase 1 placeholder: always approves. Replaced by a real HTTP call to the
 * separate Fraud Service in Phase 4 (distributed tracing).
 */
@Component
public class StubFraudCheck implements FraudCheck {

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
            if (!approved) {
                metrics.countFraudRejected();
            }
            return approved;
        } finally {
            metrics.recordFraudDuration(System.nanoTime() - start);
        }
    }
}
