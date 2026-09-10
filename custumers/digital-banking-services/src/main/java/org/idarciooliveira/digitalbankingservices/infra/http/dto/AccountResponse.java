package org.idarciooliveira.digitalbankingservices.infra.http.dto;

import org.idarciooliveira.digitalbankingservices.domain.model.Account;

import java.math.BigDecimal;
import java.util.UUID;

public record AccountResponse(
        UUID id,
        String accountNumber,
        BigDecimal balance) {

    public static AccountResponse from(Account account) {
        return new AccountResponse(
                account.getId(),
                account.getAccountNumber(),
                account.getBalance());
    }
}
