package org.idarciooliveira.fraudservice;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.stereotype.Component;

import java.util.concurrent.TimeUnit;

@Component
public class FraudMetrics {

    public static final String FRAUD_REJECTED = "bank.fraud.rejected";
    public static final String FRAUD_DURATION = "bank.fraud.duration";

    private final MeterRegistry registry;
    private final Counter fraudRejected;
    private final Timer fraudDuration;

    public FraudMetrics(MeterRegistry registry) {
        this.registry = registry;
        this.fraudRejected = Counter.builder(FRAUD_REJECTED)
                .description("Number of transfers rejected by the fraud check")
                .register(registry);
        this.fraudDuration = Timer.builder(FRAUD_DURATION)
                .description("Fraud-check latency")
                .register(registry);
    }

    public void countFraudRejected() {
        fraudRejected.increment();
    }

    public void recordFraudDuration(long nanos) {
        fraudDuration.record(nanos, TimeUnit.NANOSECONDS);
    }
}
