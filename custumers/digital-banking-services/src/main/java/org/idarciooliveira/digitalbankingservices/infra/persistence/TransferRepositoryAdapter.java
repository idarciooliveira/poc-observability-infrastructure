package org.idarciooliveira.digitalbankingservices.infra.persistence;

import org.idarciooliveira.digitalbankingservices.domain.model.Transfer;
import org.idarciooliveira.digitalbankingservices.domain.repository.TransferRepository;
import org.springframework.stereotype.Repository;

@Repository
public class TransferRepositoryAdapter implements TransferRepository {

    private final TransferJpaRepository jpaRepository;

    public TransferRepositoryAdapter(TransferJpaRepository jpaRepository) {
        this.jpaRepository = jpaRepository;
    }

    @Override
    public void save(Transfer transfer) {
        TransferEntity entity = new TransferEntity(
                transfer.getId(),
                transfer.getSourceAccountNumber(),
                transfer.getDestinationAccountNumber(),
                transfer.getAmount(),
                transfer.getCreatedAt(),
                transfer.getStatus());
        jpaRepository.save(entity);
    }
}
