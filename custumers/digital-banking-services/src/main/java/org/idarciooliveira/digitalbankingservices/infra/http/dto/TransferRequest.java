package org.idarciooliveira.digitalbankingservices.infra.http.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;

public record TransferRequest(
        @NotBlank String sourceAccountNumber,
        @NotBlank String destinationAccountNumber,
        @NotNull @DecimalMin(value = "0.01") BigDecimal amount) {
}
