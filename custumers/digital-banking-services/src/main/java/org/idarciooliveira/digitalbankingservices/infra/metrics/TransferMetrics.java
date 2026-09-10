package org.idarciooliveira.digitalbankingservices.infra.metrics;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.stereotype.Component;

import java.util.concurrent.TimeUnit;

/**
 * Business metrics for the banking domain (FR-07).
 * Infra-layer component; the domain stays metrics-free.
 * Tag values are a fixed low-cardinality set — never account numbers (FR-11).
 */
@Component
public class TransferMetrics {

    public static final String TRANSFERS_TOTAL = "bank.transfers.total";
    public static final String FRAUD_REJECTED = "bank.fraud.rejected";
    public static final String TRANSFER_DURATION = "bank.transfer.duration";
    public static final String FRAUD_DURATION = "bank.fraud.duration";

    public static final String STATUS_SUCCESS = "success";
    public static final String STATUS_FRAUD_REJECTED = "fraud_rejected";
    public static final String STATUS_INSUFFICIENT_BALANCE = "insufficient_balance";
    public static final String STATUS_ACCOUNT_NOT_FOUND = "account_not_found";
    public static final String STATUS_INVALID = "invalid";
    public static final String STATUS_ERROR = "error";

    private final MeterRegistry registry;
    private final Counter fraudRejected;
    private final Timer transferDuration;
    private final Timer fraudDuration;

    public TransferMetrics(MeterRegistry registry) {
        this.registry = registry;
        this.fraudRejected = Counter.builder(FRAUD_REJECTED)
                .description("Number of transfers rejected by the fraud check")
                .register(registry);
        this.transferDuration = Timer.builder(TRANSFER_DURATION)
                .description("End-to-end transfer processing latency")
                .register(registry);
        this.fraudDuration = Timer.builder(FRAUD_DURATION)
                .description("Fraud-check latency")
                .register(registry);
    }

    public void countTransfer(String status) {
        Counter.builder(TRANSFERS_TOTAL)
                .description("Total number of transfer attempts")
                .tag("status", status)
                .register(registry)
                .increment();
    }

    public void countFraudRejected() {
        fraudRejected.increment();
    }

    public void recordTransferDuration(long nanos) {
        transferDuration.record(nanos, TimeUnit.NANOSECONDS);
    }

    public void recordFraudDuration(long nanos) {
        fraudDuration.record(nanos, TimeUnit.NANOSECONDS);
    }
}
