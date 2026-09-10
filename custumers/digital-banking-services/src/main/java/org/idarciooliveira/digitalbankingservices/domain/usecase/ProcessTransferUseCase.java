package org.idarciooliveira.digitalbankingservices.domain.usecase;

import org.idarciooliveira.digitalbankingservices.domain.exception.AccountNotFoundException;
import org.idarciooliveira.digitalbankingservices.domain.exception.FraudRejectedException;
import org.idarciooliveira.digitalbankingservices.domain.exception.InsufficientBalanceException;
import org.idarciooliveira.digitalbankingservices.domain.model.Account;
import org.idarciooliveira.digitalbankingservices.domain.model.Transfer;
import org.idarciooliveira.digitalbankingservices.domain.repository.AccountRepository;
import org.idarciooliveira.digitalbankingservices.domain.repository.TransferRepository;

import java.math.BigDecimal;

public class ProcessTransferUseCase {

    private final AccountRepository accountRepository;
    private final TransferRepository transferRepository;
    private final FraudCheck fraudCheck;

    public ProcessTransferUseCase(AccountRepository accountRepository,
                                   TransferRepository transferRepository,
                                   FraudCheck fraudCheck) {
        this.accountRepository = accountRepository;
        this.transferRepository = transferRepository;
        this.fraudCheck = fraudCheck;
    }

    public Transfer process(String sourceAccountNumber, String destinationAccountNumber, BigDecimal amount) {
        if (amount == null || amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("Transfer amount must be greater than zero");
        }
        if (sourceAccountNumber.equals(destinationAccountNumber)) {
            throw new IllegalArgumentException("Source and destination accounts must differ");
        }

        Account source = accountRepository.findByAccountNumber(sourceAccountNumber)
                .orElseThrow(() -> new AccountNotFoundException(sourceAccountNumber));
        Account destination = accountRepository.findByAccountNumber(destinationAccountNumber)
                .orElseThrow(() -> new AccountNotFoundException(destinationAccountNumber));

        if (!source.hasSufficientBalance(amount)) {
            throw new InsufficientBalanceException(sourceAccountNumber);
        }

        if (!fraudCheck.isApproved(sourceAccountNumber, amount)) {
            throw new FraudRejectedException(sourceAccountNumber);
        }

        source.debit(amount);
        destination.credit(amount);
        accountRepository.save(source);
        accountRepository.save(destination);

        Transfer transfer = Transfer.requested(sourceAccountNumber, destinationAccountNumber, amount);
        transferRepository.save(transfer);
        return transfer;
    }
}
