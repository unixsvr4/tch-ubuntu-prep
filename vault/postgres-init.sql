-- postgres-init.sql
-- Runs automatically when the postgres container first starts.
-- Grants vault_admin the ability to create and revoke dynamic database users.
-- This is required for Vault's database secrets engine.

-- Grant CREATEROLE so Vault can create dynamic users per app instance.
-- In production: use a least-privilege Vault DB user — only what it needs.
ALTER USER vault_admin WITH CREATEROLE;

-- Create a sample payments table so dynamic users have something to connect to.
-- Vault will grant SELECT/INSERT/UPDATE on this to each dynamic credential.
CREATE TABLE IF NOT EXISTS payments (
    id            SERIAL PRIMARY KEY,
    transaction_id VARCHAR(64) NOT NULL UNIQUE,
    amount        NUMERIC(10,2) NOT NULL,
    status        VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at    TIMESTAMP DEFAULT NOW()
);

-- Insert test data so we can verify dynamic credentials can actually query
INSERT INTO payments (transaction_id, amount, status) VALUES
    ('TXN-001', 100.00, 'settled'),
    ('TXN-002', 250.50, 'pending'),
    ('TXN-003', 75.25, 'settled')
ON CONFLICT DO NOTHING;
