package org.idarciooliveira.fraudservice;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/fraud-check")
public class FraudCheckController {

    private final FraudCheckService fraudCheckService;

    public FraudCheckController(FraudCheckService fraudCheckService) {
        this.fraudCheckService = fraudCheckService;
    }

    @PostMapping
    public ResponseEntity<FraudCheckResponse> checkFraud(@Valid @RequestBody FraudCheckRequest request) {
        boolean approved = fraudCheckService.checkFraud(request.sourceAccountNumber(), request.amount());
        return ResponseEntity.ok(new FraudCheckResponse(approved));
    }
}
