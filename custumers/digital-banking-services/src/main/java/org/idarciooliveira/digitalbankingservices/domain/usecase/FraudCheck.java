package org.idarciooliveira.digitalbankingservices.domain.usecase;

import java.math.BigDecimal;

public interface FraudCheck {

    boolean isApproved(String sourceAccountNumber, BigDecimal amount);
}
