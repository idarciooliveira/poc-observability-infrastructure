package org.idarciooliveira.digitalbankingservices.infra.http;

import jakarta.validation.Valid;
import org.idarciooliveira.digitalbankingservices.domain.model.Transfer;
import org.idarciooliveira.digitalbankingservices.domain.usecase.GetTransferUseCase;
import org.idarciooliveira.digitalbankingservices.infra.application.TransferApplicationService;
import org.idarciooliveira.digitalbankingservices.infra.http.dto.TransferRequest;
import org.idarciooliveira.digitalbankingservices.infra.http.dto.TransferResponse;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
@RequestMapping("/transfers")
public class TransferController {

    private final TransferApplicationService transferApplicationService;
    private final GetTransferUseCase getTransferUseCase;

    public TransferController(TransferApplicationService transferApplicationService, GetTransferUseCase getTransferUseCase) {
        this.transferApplicationService = transferApplicationService;
        this.getTransferUseCase = getTransferUseCase;
    }

    @PostMapping
    public ResponseEntity<TransferResponse> transfer(@Valid @RequestBody TransferRequest request) {
        Transfer transfer = transferApplicationService.processTransfer(
                request.sourceAccountNumber(),
                request.destinationAccountNumber(),
                request.amount());
        return ResponseEntity.status(HttpStatus.CREATED).body(TransferResponse.from(transfer));
    }

    @GetMapping("/{id}")
    public ResponseEntity<TransferResponse> get(@PathVariable UUID id) {
        Transfer transfer = getTransferUseCase.get(id);
        return ResponseEntity.ok(TransferResponse.from(transfer));
    }
}
