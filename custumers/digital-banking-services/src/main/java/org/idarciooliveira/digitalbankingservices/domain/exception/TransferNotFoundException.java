package org.idarciooliveira.digitalbankingservices.domain.exception;

import java.util.UUID;

public class TransferNotFoundException extends RuntimeException {

    public TransferNotFoundException(UUID id) {
        super("Transfer not found: " + id);
    }
}
