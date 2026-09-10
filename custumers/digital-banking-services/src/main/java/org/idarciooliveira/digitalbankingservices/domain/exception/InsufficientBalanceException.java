package org.idarciooliveira.digitalbankingservices.domain.exception;

public class InsufficientBalanceException extends RuntimeException {

    public InsufficientBalanceException(String accountNumber) {
        super("Insufficient balance on account: " + accountNumber);
    }
}
