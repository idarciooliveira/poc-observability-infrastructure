package org.idarciooliveira.digitalbankingservices.domain.exception;

public class AccountAlreadyExistException extends RuntimeException {
    public AccountAlreadyExistException(String accountNumber) {
        super("Account already exist: " + accountNumber);
    }
}
