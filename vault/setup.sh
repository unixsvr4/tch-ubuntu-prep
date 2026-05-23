#!/usr/bin/env bash
# ============================================================
# vault/setup.sh — Configure Vault for payment platform demo
# ============================================================
# Run: make vault-setup
# Requires: docker compose up (vault + postgres must be running)
#
# What this script does:
#   1. Enables the database secrets engine
#   2. Connects Vault to the Postgres container as vault_admin
#   3. Creates a role that issues 1h dynamic credentials
#   4. Writes the payment-app Vault policy (least privilege)
#
# After this runs:
#   make vault-creds         → get a live dynamic credential
#   make vault-policy-test   → prove the policy restricts access
#   make vault-list          → see all engines + active leases
# ============================================================
set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-root}"

export VAULT_ADDR VAULT_TOKEN

# ── 1. Verify Vault is running ────────────────────────────────────────────
echo "==> Checking Vault status..."
if ! vault status > /dev/null 2>&1; then
    echo "ERROR: Vault is not reachable at $VAULT_ADDR"
    echo "       Run: make up  and wait for containers to be healthy"
    exit 1
fi
echo "    Vault is running (dev mode, auto-unsealed)"

# ── 2. Verify Postgres is reachable ───────────────────────────────────────
echo ""
echo "==> Checking PostgreSQL connectivity..."
if ! docker exec tch-ubuntu-postgres pg_isready -U vault_admin -q 2>/dev/null; then
    echo "ERROR: PostgreSQL is not ready"
    echo "       Run: make up  and wait for containers to be healthy"
    exit 1
fi
echo "    PostgreSQL is ready"

# ── 3. Enable database secrets engine ────────────────────────────────────
echo ""
echo "==> Enabling database secrets engine..."
# 2>/dev/null suppresses "already enabled" error when re-running
vault secrets enable database 2>/dev/null && echo "    Enabled" || echo "    Already enabled"

# ── 4. Configure connection to PostgreSQL ────────────────────────────────
echo ""
echo "==> Configuring Vault ↔ PostgreSQL connection..."
# Vault connects as vault_admin and uses {{username}}/{{password}} template
# to create/revoke dynamic credentials.
# The container is on the docker-compose network; use tch-ubuntu-postgres as hostname.
vault write database/config/payments-db \
    plugin_name=postgresql-database-plugin \
    allowed_roles="payment-role" \
    connection_url="postgresql://{{username}}:{{password}}@tch-ubuntu-postgres:5432/payments?sslmode=disable" \
    username="vault_admin" \
    password="vault_admin_pass"

echo "    PostgreSQL connection configured"

# ── 5. Create the dynamic credential role ────────────────────────────────
echo ""
echo "==> Creating 'payment-role' (TTL: 1h, max: 24h)..."
# creation_statements: SQL Vault runs when issuing credentials
# revocation_statements: SQL Vault runs when credentials expire or are revoked
vault write database/roles/payment-role \
    db_name=payments-db \
    creation_statements="
        CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';
        GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";
        GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\";
    " \
    revocation_statements="
        REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM \"{{name}}\";
        REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM \"{{name}}\";
        DROP ROLE IF EXISTS \"{{name}}\";
    " \
    default_ttl="1h" \
    max_ttl="24h"

echo "    Role 'payment-role' created"

# ── 6. Write the payment-app Vault policy ────────────────────────────────
echo ""
echo "==> Writing payment-app policy (least privilege)..."
vault policy write payment-app vault/policies/payment-app.hcl
echo "    Policy 'payment-app' written"

# ── 7. Test: verify we can actually get a credential ─────────────────────
echo ""
echo "==> Quick test — requesting one credential to verify setup..."
TEST_CREDS=$(vault read -format=json database/creds/payment-role)
TEST_USER=$(echo "$TEST_CREDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['username'])")
echo "    Test credential issued: $TEST_USER"
echo "    (This credential will expire in 1 hour — Vault auto-revokes)"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Vault dynamic credentials ready!                       ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  make vault-creds        → get a live credential        ║"
echo "║  make vault-policy-test  → test least-privilege policy  ║"
echo "║  make vault-list         → show engines + leases        ║"
echo "║  make vault-revoke-all   → revoke all credentials       ║"
echo "╚══════════════════════════════════════════════════════════╝"
