package org.idarciooliveira.digitalbankingservices.infra.http;

import jakarta.validation.Valid;
import org.idarciooliveira.digitalbankingservices.domain.model.Account;
import org.idarciooliveira.digitalbankingservices.domain.usecase.CreateAccountUsecase;
import org.idarciooliveira.digitalbankingservices.domain.usecase.GetAccountUseCase;
import org.idarciooliveira.digitalbankingservices.infra.http.dto.AccountRequest;
import org.idarciooliveira.digitalbankingservices.infra.http.dto.AccountResponse;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/accounts")
public class AccountController {

    private final CreateAccountUsecase createAccountUsecase;
    private final GetAccountUseCase getAccountUseCase;

    public AccountController(CreateAccountUsecase createAccountUsecase, GetAccountUseCase getAccountUseCase) {
        this.createAccountUsecase = createAccountUsecase;
        this.getAccountUseCase = getAccountUseCase;
    }

    @PostMapping()
    public ResponseEntity<AccountResponse> create(@Valid @RequestBody AccountRequest accountRequest){
        Account account = createAccountUsecase
                .process(accountRequest.accountNumber(),accountRequest.balance());
        return ResponseEntity.status(HttpStatus.CREATED).body(AccountResponse.from(account));
    }

    @GetMapping("/{accountNumber}")
    public ResponseEntity<AccountResponse> get(@PathVariable String accountNumber) {
        Account account = getAccountUseCase.get(accountNumber);
        return ResponseEntity.ok(AccountResponse.from(account));
    }
}
