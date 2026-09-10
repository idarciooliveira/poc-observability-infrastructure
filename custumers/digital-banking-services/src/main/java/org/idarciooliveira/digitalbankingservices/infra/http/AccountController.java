package org.idarciooliveira.digitalbankingservices.infra.http;

import jakarta.validation.Valid;
import org.idarciooliveira.digitalbankingservices.domain.model.Account;
import org.idarciooliveira.digitalbankingservices.domain.usecase.CreateAccountUsecase;
import org.idarciooliveira.digitalbankingservices.infra.http.dto.AccountRequest;
import org.idarciooliveira.digitalbankingservices.infra.http.dto.AccountResponse;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/accounts")
public class AccountController {

    private final CreateAccountUsecase createAccountUsecase;

    public AccountController(CreateAccountUsecase createAccountUsecase) {
        this.createAccountUsecase = createAccountUsecase;
    }

    @PostMapping()
    public ResponseEntity<AccountResponse> create(@Valid @RequestBody AccountRequest accountRequest){
        Account account = createAccountUsecase
                .process(accountRequest.accountNumber(),accountRequest.balance());
        return ResponseEntity.status(HttpStatus.CREATED).body(AccountResponse.from(account));
    }
}
