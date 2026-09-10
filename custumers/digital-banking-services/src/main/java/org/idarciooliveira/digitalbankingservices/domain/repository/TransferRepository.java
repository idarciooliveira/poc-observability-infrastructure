package org.idarciooliveira.digitalbankingservices.domain.repository;

import org.idarciooliveira.digitalbankingservices.domain.model.Transfer;

import java.util.Optional;
import java.util.UUID;

public interface TransferRepository {

    void save(Transfer transfer);

    Optional<Transfer> findById(UUID id);
}
