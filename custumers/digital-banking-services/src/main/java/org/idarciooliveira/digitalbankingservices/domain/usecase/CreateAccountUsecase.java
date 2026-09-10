package org.idarciooliveira.digitalbankingservices.domain.usecase;

import org.idarciooliveira.digitalbankingservices.domain.exception.AccountAlreadyExistException;
import org.idarciooliveira.digitalbankingservices.domain.model.Account;
import org.idarciooliveira.digitalbankingservices.domain.repository.AccountRepository;

import java.math.BigDecimal;
import java.util.UUID;

public class CreateAccountUsecase {
    private final AccountRepository accountRepository;

    public CreateAccountUsecase(AccountRepository accountRepository){
        this.accountRepository = accountRepository;
    }

    public Account process(String accountNumber, BigDecimal balance){
        boolean accountExist =  accountRepository.findByAccountNumber(accountNumber).isPresent();
        if(accountExist){
            throw  new AccountAlreadyExistException(accountNumber);
        }

        Account account = new Account(UUID.randomUUID(), accountNumber, balance);
        accountRepository.save(account);

        return account;
    }
}

