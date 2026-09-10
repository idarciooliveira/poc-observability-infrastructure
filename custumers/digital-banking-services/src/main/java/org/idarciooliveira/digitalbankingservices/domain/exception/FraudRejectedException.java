package org.idarciooliveira.digitalbankingservices.domain.exception;

public class FraudRejectedException extends RuntimeException {

    public FraudRejectedException(String sourceAccountNumber) {
        super("Fraud check rejected transfer from account: " + sourceAccountNumber);
    }
}
