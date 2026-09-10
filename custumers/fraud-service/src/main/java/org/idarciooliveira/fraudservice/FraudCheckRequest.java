package org.idarciooliveira.fraudservice;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;

public record FraudCheckRequest(
    @NotBlank String sourceAccountNumber,
    @NotNull BigDecimal amount
) {}
