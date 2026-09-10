package org.idarciooliveira.digitalbankingservices.domain.repository;

import org.idarciooliveira.digitalbankingservices.domain.model.Account;

import java.util.Optional;

public interface AccountRepository {

    Optional<Account> findByAccountNumber(String accountNumber);

    void save(Account account);
}
