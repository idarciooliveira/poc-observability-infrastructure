package org.idarciooliveira.digitalbankingservices.infra.http.dto;

import org.idarciooliveira.digitalbankingservices.domain.model.Transfer;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

public record TransferResponse(
        UUID id,
        String sourceAccountNumber,
        String destinationAccountNumber,
        BigDecimal amount,
        Instant createdAt,
        String status) {

    public static TransferResponse from(Transfer transfer) {
        return new TransferResponse(
                transfer.getId(),
                transfer.getSourceAccountNumber(),
                transfer.getDestinationAccountNumber(),
                transfer.getAmount(),
                transfer.getCreatedAt(),
                transfer.getStatus().name());
    }
}
