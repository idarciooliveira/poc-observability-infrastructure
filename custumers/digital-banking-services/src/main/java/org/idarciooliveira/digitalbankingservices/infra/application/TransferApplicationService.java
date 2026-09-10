package org.idarciooliveira.digitalbankingservices.infra.application;

import org.idarciooliveira.digitalbankingservices.domain.model.Transfer;
import org.idarciooliveira.digitalbankingservices.domain.usecase.ProcessTransferUseCase;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;

/**
 * Application-layer transaction boundary.
 * Keeps the domain use case a pure POJO; Spring concerns (@Transactional)
 * live here in infra.
 */
@Service
public class TransferApplicationService {

    private final ProcessTransferUseCase processTransferUseCase;

    public TransferApplicationService(ProcessTransferUseCase processTransferUseCase) {
        this.processTransferUseCase = processTransferUseCase;
    }

    @Transactional
    public Transfer processTransfer(String sourceAccountNumber, String destinationAccountNumber, BigDecimal amount) {
        return processTransferUseCase.process(sourceAccountNumber, destinationAccountNumber, amount);
    }
}
