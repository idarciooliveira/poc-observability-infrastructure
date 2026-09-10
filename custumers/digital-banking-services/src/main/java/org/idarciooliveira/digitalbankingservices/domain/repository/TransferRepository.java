package org.idarciooliveira.digitalbankingservices.domain.repository;

import org.idarciooliveira.digitalbankingservices.domain.model.Transfer;

public interface TransferRepository {

    void save(Transfer transfer);
}
