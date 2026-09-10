package org.idarciooliveira.digitalbankingservices.domain.model;

public enum TransferStatus {
    APPROVED,
    REJECTED_INSUFFICIENT_BALANCE,
    REJECTED_ACCOUNT_NOT_FOUND,
    REJECTED_FRAUD
}
