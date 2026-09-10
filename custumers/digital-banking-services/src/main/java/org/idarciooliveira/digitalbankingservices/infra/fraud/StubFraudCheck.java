package org.idarciooliveira.digitalbankingservices.infra.fraud;

import org.idarciooliveira.digitalbankingservices.domain.usecase.FraudCheck;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;

/**
 * Phase 1 placeholder: always approves. Replaced by a real HTTP call to the
 * separate Fraud Service in Phase 4 (distributed tracing).
 */
@Component
public class StubFraudCheck implements FraudCheck {

    private static final BigDecimal SUSPICIOUS_THRESHOLD = new BigDecimal("10000");

    @Override
    public boolean isApproved(String sourceAccountNumber, BigDecimal amount) {
        return amount.compareTo(SUSPICIOUS_THRESHOLD) < 0;
    }
}
