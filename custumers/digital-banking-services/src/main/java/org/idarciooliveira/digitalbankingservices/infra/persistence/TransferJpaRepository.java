package org.idarciooliveira.digitalbankingservices.infra.persistence;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface TransferJpaRepository extends JpaRepository<TransferEntity, UUID> {
}
