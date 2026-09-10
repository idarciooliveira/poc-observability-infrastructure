package org.idarciooliveira.fraudservice;

import io.opentelemetry.instrumentation.annotations.WithSpan;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.concurrent.ThreadLocalRandom;

@Service
public class FraudCheckService {

    private static final Logger log = LoggerFactory.getLogger(FraudCheckService.class);
    private static final BigDecimal SUSPICIOUS_THRESHOLD = new BigDecimal("10000");

    private final FraudMetrics metrics;
    private final long chaosLatencyMs;
    private final double chaosRejectRate;

    public FraudCheckService(
            FraudMetrics metrics,
            // Phase 8 fault injection (env-driven, no rebuild to toggle).
            // CHAOS_LATENCY_MS > 2000 also trips the API's 2s fraud-check
            // timeout, exercising the timeout error path for free.
            @Value("${CHAOS_LATENCY_MS:0}") long chaosLatencyMs,
            @Value("${CHAOS_REJECT_RATE:0}") double chaosRejectRate) {
        this.metrics = metrics;
        this.chaosLatencyMs = chaosLatencyMs;
        this.chaosRejectRate = chaosRejectRate;
        if (chaosLatencyMs > 0 || chaosRejectRate > 0) {
            log.warn("chaos enabled latency_ms={} reject_rate={}", chaosLatencyMs, chaosRejectRate);
        }
    }

    @WithSpan("fraud.check")
    public boolean checkFraud(String sourceAccountNumber, BigDecimal amount) {
        long start = System.nanoTime();
        try {
            if (chaosLatencyMs > 0) {
                sleepUninterruptibly(chaosLatencyMs);
            }
            boolean approved = amount.compareTo(SUSPICIOUS_THRESHOLD) < 0;
            String reason = approved ? null : "suspicious_amount";
            if (approved && chaosRejectRate > 0
                    && ThreadLocalRandom.current().nextDouble() < chaosRejectRate) {
                approved = false;
                reason = "chaos_forced";
            }
            if (approved) {
                log.info("fraud.check status=approved source={} amount={}", sourceAccountNumber, amount);
            } else {
                log.warn("fraud.check status=rejected source={} amount={} reason={}",
                        sourceAccountNumber, amount, reason);
                metrics.countFraudRejected();
            }
            return approved;
        } finally {
            metrics.recordFraudDuration(System.nanoTime() - start);
        }
    }

    private void sleepUninterruptibly(long millis) {
        long deadline = System.currentTimeMillis() + millis;
        long remaining;
        while ((remaining = deadline - System.currentTimeMillis()) > 0) {
            try {
                Thread.sleep(remaining);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
        }
    }
}
