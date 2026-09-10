package org.idarciooliveira.riskservice;

import io.opentelemetry.instrumentation.annotations.WithSpan;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.UUID;

@Service
public class RiskCheckService {

    private static final Logger log = LoggerFactory.getLogger(RiskCheckService.class);
    private static final BigDecimal HIGH_VALUE_THRESHOLD = new BigDecimal("50000");
    private static final BigDecimal COVERAGE_EXHAUSTION_RATIO = new BigDecimal("0.80");

    private final RiskMetrics metrics;

    public RiskCheckService(RiskMetrics metrics) {
        this.metrics = metrics;
    }

    @WithSpan("risk.assessment")
    public RiskCheckResponse checkRisk(UUID policyId, BigDecimal claimAmount, BigDecimal coverageLimit) {
        long start = System.nanoTime();
        try {
            // Check for high-value claims
            if (claimAmount.compareTo(HIGH_VALUE_THRESHOLD) > 0) {
                log.warn("risk.assessment status=rejected policy={} amount={} reason=high_value",
                         policyId, claimAmount);
                metrics.countRiskRejected();
                return new RiskCheckResponse(false, "high_value");
            }

            // Check for coverage exhaustion risk (claim > 80% of coverage limit)
            BigDecimal exhaustionThreshold = coverageLimit.multiply(COVERAGE_EXHAUSTION_RATIO);
            if (claimAmount.compareTo(exhaustionThreshold) > 0) {
                log.warn("risk.assessment status=rejected policy={} amount={} coverageLimit={} reason=coverage_exhaustion",
                         policyId, claimAmount, coverageLimit);
                metrics.countRiskRejected();
                return new RiskCheckResponse(false, "coverage_exhaustion");
            }

            // Approve claim
            log.info("risk.assessment status=approved policy={} amount={} coverageLimit={}",
                     policyId, claimAmount, coverageLimit);
            return new RiskCheckResponse(true, "approved");
        } finally {
            metrics.recordRiskDuration(System.nanoTime() - start);
        }
    }
}
