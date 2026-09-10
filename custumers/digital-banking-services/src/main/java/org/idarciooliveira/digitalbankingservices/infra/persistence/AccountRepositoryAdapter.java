package org.idarciooliveira.digitalbankingservices.infra.persistence;

import io.opentelemetry.instrumentation.annotations.WithSpan;
import org.idarciooliveira.digitalbankingservices.domain.model.Account;
import org.idarciooliveira.digitalbankingservices.domain.repository.AccountRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

@Repository
public class AccountRepositoryAdapter implements AccountRepository {

    private final AccountJpaRepository jpaRepository;

    public AccountRepositoryAdapter(AccountJpaRepository jpaRepository) {
        this.jpaRepository = jpaRepository;
    }

    @Override
    public Optional<Account> findByAccountNumber(String accountNumber) {
        return jpaRepository.findByAccountNumber(accountNumber)
                .map(entity -> new Account(entity.getId(), entity.getAccountNumber(), entity.getBalance()));
    }

    @WithSpan("database.update")
    @Override
    public void save(Account account) {
        AccountEntity entity = jpaRepository.findById(account.getId())
                .orElse(new AccountEntity(account.getId(), account.getAccountNumber(), account.getBalance()));
        entity.setBalance(account.getBalance());
        jpaRepository.save(entity);
    }
}
