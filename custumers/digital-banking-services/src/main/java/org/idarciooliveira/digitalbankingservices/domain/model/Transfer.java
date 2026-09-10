package org.idarciooliveira.digitalbankingservices.domain.model;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

public class Transfer {

    private final UUID id;
    private final String sourceAccountNumber;
    private final String destinationAccountNumber;
    private final BigDecimal amount;
    private final Instant createdAt;
    private TransferStatus status;

    public Transfer(UUID id, String sourceAccountNumber, String destinationAccountNumber,
                     BigDecimal amount, Instant createdAt, TransferStatus status) {
        this.id = id;
        this.sourceAccountNumber = sourceAccountNumber;
        this.destinationAccountNumber = destinationAccountNumber;
        this.amount = amount;
        this.createdAt = createdAt;
        this.status = status;
    }

    public static Transfer requested(String sourceAccountNumber, String destinationAccountNumber, BigDecimal amount) {
        return new Transfer(UUID.randomUUID(), sourceAccountNumber, destinationAccountNumber,
                amount, Instant.now(), TransferStatus.APPROVED);
    }

    public void reject(TransferStatus reason) {
        this.status = reason;
    }

    public UUID getId() {
        return id;
    }

    public String getSourceAccountNumber() {
        return sourceAccountNumber;
    }

    public String getDestinationAccountNumber() {
        return destinationAccountNumber;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public TransferStatus getStatus() {
        return status;
    }
}
