package org.idarciooliveira.digitalbankingservices.domain.usecase;

import org.idarciooliveira.digitalbankingservices.domain.exception.TransferNotFoundException;
import org.idarciooliveira.digitalbankingservices.domain.model.Transfer;
import org.idarciooliveira.digitalbankingservices.domain.repository.TransferRepository;

import java.util.UUID;

public class GetTransferUseCase {

    private final TransferRepository transferRepository;

    public GetTransferUseCase(TransferRepository transferRepository) {
        this.transferRepository = transferRepository;
    }

    public Transfer get(UUID id) {
        return transferRepository.findById(id)
                .orElseThrow(() -> new TransferNotFoundException(id));
    }
}
