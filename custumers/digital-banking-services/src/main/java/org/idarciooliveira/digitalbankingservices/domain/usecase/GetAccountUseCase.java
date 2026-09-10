package org.idarciooliveira.digitalbankingservices.domain.usecase;

import org.idarciooliveira.digitalbankingservices.domain.exception.AccountNotFoundException;
import org.idarciooliveira.digitalbankingservices.domain.model.Account;
import org.idarciooliveira.digitalbankingservices.domain.repository.AccountRepository;

public class GetAccountUseCase {

    private final AccountRepository accountRepository;

    public GetAccountUseCase(AccountRepository accountRepository) {
        this.accountRepository = accountRepository;
    }

    public Account get(String accountNumber) {
        return accountRepository.findByAccountNumber(accountNumber)
                .orElseThrow(() -> new AccountNotFoundException(accountNumber));
    }
}
