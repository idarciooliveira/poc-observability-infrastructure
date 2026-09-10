package org.idarciooliveira.digitalbankingservices.infra.config;

import org.idarciooliveira.digitalbankingservices.domain.repository.AccountRepository;
import org.idarciooliveira.digitalbankingservices.domain.repository.TransferRepository;
import org.idarciooliveira.digitalbankingservices.domain.usecase.CreateAccountUsecase;
import org.idarciooliveira.digitalbankingservices.domain.usecase.FraudCheck;
import org.idarciooliveira.digitalbankingservices.domain.usecase.GetAccountUseCase;
import org.idarciooliveira.digitalbankingservices.domain.usecase.GetTransferUseCase;
import org.idarciooliveira.digitalbankingservices.domain.usecase.ProcessTransferUseCase;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class UseCaseConfig {

    @Bean
    public ProcessTransferUseCase processTransferUseCase(AccountRepository accountRepository,
                                                           TransferRepository transferRepository,
                                                           FraudCheck fraudCheck) {
        return new ProcessTransferUseCase(accountRepository, transferRepository, fraudCheck);
    }

    @Bean
    public CreateAccountUsecase createAccountUsecase(AccountRepository accountRepository){
        return  new CreateAccountUsecase(accountRepository);
    }

    @Bean
    public GetAccountUseCase getAccountUseCase(AccountRepository accountRepository) {
        return new GetAccountUseCase(accountRepository);
    }

    @Bean
    public GetTransferUseCase getTransferUseCase(TransferRepository transferRepository) {
        return new GetTransferUseCase(transferRepository);
    }
}
