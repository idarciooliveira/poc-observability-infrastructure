package org.idarciooliveira.fraudservice;

import io.opentelemetry.instrumentation.annotations.WithSpan;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;

@Service
public class FraudCheckService {

    private static final Logger log = LoggerFactory.getLogger(FraudCheckService.class);
    private static final BigDecimal SUSPICIOUS_THRESHOLD = new BigDecimal("10000");

    private final FraudMetrics metrics;

    public FraudCheckService(FraudMetrics metrics) {
        this.metrics = metrics;
    }

    @WithSpan("fraud.check")
    public boolean checkFraud(String sourceAccountNumber, BigDecimal amount) {
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
