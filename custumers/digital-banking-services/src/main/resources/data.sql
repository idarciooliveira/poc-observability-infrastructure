INSERT INTO accounts (id, account_number, balance) VALUES
    ('a3c1f9a0-1111-4a2a-9c1a-000000000001', 'BANK-0001', 5000.00),
    ('a3c1f9a0-1111-4a2a-9c1a-000000000002', 'BANK-0002', 1500.00),
    -- Phase 8 seed: high-balance account for the fraud-reject demo.
    -- Fraud rejects amounts >= 10000, but balance is checked FIRST, so the
    -- demo needs an account that can cover a suspicious amount.
    ('a3c1f9a0-1111-4a2a-9c1a-000000000003', 'BANK-0003', 50000.00)
ON CONFLICT (account_number) DO NOTHING;
