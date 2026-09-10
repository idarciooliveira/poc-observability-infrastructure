INSERT INTO accounts (id, account_number, balance) VALUES
    ('a3c1f9a0-1111-4a2a-9c1a-000000000001', 'BANK-0001', 5000.00),
    ('a3c1f9a0-1111-4a2a-9c1a-000000000002', 'BANK-0002', 1500.00)
ON CONFLICT (account_number) DO NOTHING;
