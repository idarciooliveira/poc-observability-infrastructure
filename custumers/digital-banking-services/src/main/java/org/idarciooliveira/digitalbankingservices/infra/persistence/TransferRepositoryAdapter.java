package org.idarciooliveira.digitalbankingservices.infra.persistence;

import org.idarciooliveira.digitalbankingservices.domain.model.Transfer;
import org.idarciooliveira.digitalbankingservices.domain.repository.TransferRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

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

    @Override
    public Optional<Transfer> findById(UUID id) {
        return jpaRepository.findById(id)
                .map(entity -> new Transfer(
                        entity.getId(),
                        entity.getSourceAccountNumber(),
                        entity.getDestinationAccountNumber(),
                        entity.getAmount(),
                        entity.getCreatedAt(),
                        entity.getStatus()));
    }
}
