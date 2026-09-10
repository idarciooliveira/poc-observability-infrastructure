package org.idarciooliveira.digitalbankingservices.infra.application;

import io.opentelemetry.instrumentation.annotations.WithSpan;
import org.idarciooliveira.digitalbankingservices.domain.exception.AccountNotFoundException;
import org.idarciooliveira.digitalbankingservices.domain.exception.FraudRejectedException;
import org.idarciooliveira.digitalbankingservices.domain.exception.InsufficientBalanceException;
import org.idarciooliveira.digitalbankingservices.domain.model.Transfer;
import org.idarciooliveira.digitalbankingservices.domain.usecase.ProcessTransferUseCase;
import org.idarciooliveira.digitalbankingservices.infra.metrics.TransferMetrics;
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
    private final TransferMetrics metrics;

    public TransferApplicationService(ProcessTransferUseCase processTransferUseCase, TransferMetrics metrics) {
        this.processTransferUseCase = processTransferUseCase;
        this.metrics = metrics;
    }

    @WithSpan("transfer.process")
    @Transactional
    public Transfer processTransfer(String sourceAccountNumber, String destinationAccountNumber, BigDecimal amount) {
        long start = System.nanoTime();
        try {
            Transfer transfer = processTransferUseCase.process(sourceAccountNumber, destinationAccountNumber, amount);
            metrics.countTransfer(TransferMetrics.STATUS_SUCCESS);
            metrics.recordTransferDuration(System.nanoTime() - start);
            return transfer;
        } catch (FraudRejectedException e) {
            metrics.countTransfer(TransferMetrics.STATUS_FRAUD_REJECTED);
            metrics.recordTransferDuration(System.nanoTime() - start);
            throw e;
        } catch (InsufficientBalanceException e) {
            metrics.countTransfer(TransferMetrics.STATUS_INSUFFICIENT_BALANCE);
            metrics.recordTransferDuration(System.nanoTime() - start);
            throw e;
        } catch (AccountNotFoundException e) {
            metrics.countTransfer(TransferMetrics.STATUS_ACCOUNT_NOT_FOUND);
            metrics.recordTransferDuration(System.nanoTime() - start);
            throw e;
        } catch (IllegalArgumentException e) {
            metrics.countTransfer(TransferMetrics.STATUS_INVALID);
            metrics.recordTransferDuration(System.nanoTime() - start);
            throw e;
        } catch (RuntimeException e) {
            metrics.countTransfer(TransferMetrics.STATUS_ERROR);
            metrics.recordTransferDuration(System.nanoTime() - start);
            throw e;
        }
    }
}
