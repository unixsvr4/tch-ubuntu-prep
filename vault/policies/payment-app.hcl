# ============================================================
# Vault Policy: payment-app
# ============================================================
# Principle: least privilege — allow ONLY what the payment app needs.
# Everything else is implicitly denied (Vault default).
#
# This policy would be attached to:
#   - EC2 instances running the payment service (via aws auth method)
#   - ECS tasks (via kubernetes or aws auth method)
#   - CI/CD pipeline runners (via approle auth method)
#
# PCI-DSS alignment:
#   - 7.2: access restricted to what the service needs to function
#   - 10.3: all access is logged in Vault audit log
# ============================================================

# ── Dynamic Database Credentials ────────────────────────────────────────
# The payment app requests a fresh DB credential at startup.
# Each instance gets a unique user with 1h TTL — never a shared password.
# PCI-DSS 8.2.2: no shared accounts; 8.3.9: automatic rotation.
path "database/creds/payment-role" {
  capabilities = ["read"]   # ONLY read — cannot create roles or modify config
}

# ── Application Secrets (KV v2) ──────────────────────────────────────────
# Static secrets the app needs: Stripe API key, internal service tokens.
# Scoped to the payments/* path — cannot read other teams' secrets.
path "secret/data/payments/*" {
  capabilities = ["read"]   # read-only — app cannot write/update its own secrets
}

# Read the metadata (for TTL info, versioning) but not the actual secret values
path "secret/metadata/payments/*" {
  capabilities = ["read", "list"]
}

# ── Token Self-Management ─────────────────────────────────────────────────
# Allow the app to look up and renew its own token.
# Cannot create new tokens or modify policies.
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

# ── Explicitly Deny Everything Else ──────────────────────────────────────
# Vault denies by default, but being explicit is good practice —
# it documents intent and prevents confusion.
path "sys/*" {
  capabilities = ["deny"]   # Cannot access Vault system configuration
}

path "auth/*" {
  capabilities = ["deny"]   # Cannot create or modify auth methods
}

# Note: All access through this policy is logged in the Vault audit log
# including: timestamp, caller IP, path, capabilities used, result.
# This satisfies PCI-DSS 10.3: all access to audit logs is traceable.
