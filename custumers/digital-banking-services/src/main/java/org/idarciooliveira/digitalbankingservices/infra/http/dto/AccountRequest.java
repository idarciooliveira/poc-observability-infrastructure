package org.idarciooliveira.digitalbankingservices.infra.http.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;

public record AccountRequest(
        @NotBlank String accountNumber,
        @NotNull @DecimalMin(value = "0") BigDecimal balance) {
}

