# tch-ubuntu-prep — TCH / Assessment Practice Lab (Ubuntu 24.04)

Hands-on practice environment for the **55-minute Verify assessment**.  
Everything runs locally on **Ubuntu 24.04 LTS with Docker Engine CE**. No AWS account needed.

---

## What's in this repo

```
tch-ubuntu-prep/
├── terraform/
│   ├── day1-bad/        ← All 10 insecure examples — run checkov, see every issue flagged
│   ├── day1-good/       ← All 10 secure fixes — terraform validate + checkov clean
│   ├── day3-resilience/ ← Route53 failover + RDS Multi-AZ + ECS auto-scaling
│   ├── day4-bugs/       ← 5 spot-the-bug exercises (from Day 4.2 of prep file)
│   └── localstack/      ← Actually deployable — terraform apply against LocalStack
├── ansible/
│   ├── playbooks/
│   │   ├── hardening.yml      ← PCI-DSS CIS Level 2 hardening (runs against Ubuntu container)
│   │   ├── secrets-bad.yml    ← 5 anti-patterns (annotated, never runs)
│   │   └── secrets-good.yml   ← Corrected versions (actually runs)
│   ├── group_vars/prod/       ← ansible-vault encrypted variable example
│   └── templates/             ← Jinja2 app config template
├── vault/
│   ├── setup.sh               ← Configure Vault dynamic DB credentials (fully automated)
│   ├── test-creds.sh          ← Request and verify a live dynamic credential
│   └── policies/payment-app.hcl ← Vault least-privilege policy
├── docker/ansible-target/     ← Ubuntu 22.04 container with sshd + auditd
├── docker-compose.yml         ← Vault + PostgreSQL + LocalStack + Ansible target
└── scripts/
    ├── install-tools.sh       ← brew install everything
    └── scan-all.sh            ← Run all scanners on all Terraform directories
```

---

## Quick Start (entire setup in ~10 minutes)

> **All `make` commands must be run from inside the `tch-ubuntu-prep/` directory.**
> ```bash
> cd tch-ubuntu-prep   # do this once — all commands below assume you're here
> ```

### Step 1 — Install tools (one-time)

```bash
cd tch-ubuntu-prep
sudo bash scripts/install-tools.sh   # requires sudo for apt + docker install
# or: make install-tools
```

Installs via `apt`/`pip3`: `docker` (Engine CE), `terraform`, `vault`, `ansible`, `checkov`, `tfsec`, `trivy`, `awscli`  
Requires `sudo`. Script is idempotent — safe to re-run.

### Step 2 — Generate SSH key + build containers (one-time)

```bash
make setup
```

Generates `ansible/demo_key` (ed25519 SSH key for Ansible) and builds the Ubuntu target container.

### Step 3 — Start all services

```bash
make up
```

Starts 4 containers:

| Container | How to access | Protocol |
|-----------|--------------|----------|
| `tch-ubuntu-vault` | Chrome → http://localhost:8200 (token: `root`) | HTTP — browser works |
| `tch-ubuntu-postgres` | `psql -h localhost -p 5432 -U vault_admin -d payments` | PostgreSQL wire — **not a browser** |
| `tch-ubuntu-localstack` | `curl http://localhost:4566/_localstack/health` | HTTP — use curl or aws CLI, not browser root |
| `tch-ubuntu-ansible-target` | `ssh -i ansible/demo_key -p 2222 root@localhost` | SSH — **not a browser** |

> **Only Vault has a browser UI.** PostgreSQL speaks the Postgres wire protocol; Ansible target speaks SSH;
> LocalStack has an HTTP API but no browser UI — verify it with `curl` or `make status`.

---

## Day 1 — Terraform Security Scanning

### See all 10 issues flagged by checkov

```bash
make scan-bad
```

Expected output: checkov flags `CKV_AWS_41` (hardcoded creds), `CKV_AWS_25` (open SG),
`CKV_AWS_3` (unencrypted S3), `CKV_AWS_1` (wildcard IAM), `CKV_AWS_16` (unencrypted RDS),
`CKV_AWS_93` (unencrypted state), `CKV_AWS_79` (no IMDSv2), `CKV_AWS_7` (no KMS rotation), etc.

### Verify the good examples are clean

```bash
make scan-good
make validate-good
```

`validate-good` runs `terraform validate` on `day1-good/` and `day3-resilience/` — both must pass.

### Run all scanners on all directories

```bash
make scan-all
```

Shows a per-directory summary: bad = many failures, good = zero.

### Apply the good examples to LocalStack

```bash
make localstack-init   # download terraform providers (one-time)
make localstack-plan   # see what would be created
make localstack-apply  # actually create resources in LocalStack
```

Verify the resources exist:
```bash
aws --endpoint-url=http://localhost:4566 s3 ls
aws --endpoint-url=http://localhost:4566 kms list-keys
aws --endpoint-url=http://localhost:4566 dynamodb list-tables
aws --endpoint-url=http://localhost:4566 secretsmanager list-secrets
```

---

## Day 2 — Vault Dynamic Credentials

### Configure Vault (run once after `make up`)

```bash
make vault-setup
```

This script:
1. Enables the database secrets engine
2. Configures Vault → PostgreSQL connection (as vault_admin)
3. Creates `payment-role` (TTL 1h, max 24h)
4. Writes the `payment-app` least-privilege policy

### Get a live dynamic credential

```bash
make vault-creds
```

Shows:
- The unique `v-payment-role-XXXXX` username Vault generated
- TTL (auto-expires in 1 hour)
- A live PostgreSQL query using those credentials
- PCI-DSS compliance summary (req 8.2.2 + 8.3.9)

### Explore Vault interactively

```bash
make vault-list          # show secret engines + active leases
make vault-policy-test   # prove payment-app policy blocks sys/ access
make vault-revoke-all    # revoke all active credentials
```

Manual Vault exploration:
```bash
export VAULT_ADDR=http://localhost:8200 VAULT_TOKEN=root

# Read a credential manually
vault read database/creds/payment-role

# See the policy
vault policy read payment-app

# List active leases
vault list sys/leases/lookup/database/creds/payment-role
```

### Vault UI

Open http://localhost:8200, enter token `root`.  
Navigate to: Secrets → database → payment-role → Generate credentials

---

## Day 2 — Ansible Hardening

### Test connectivity

```bash
make ansible-ping
```

Expected: `ansible-target | SUCCESS => {"ping": "pong"}`

### Dry run (no changes)

```bash
make ansible-check
```

Shows every task and what would change with `--check --diff`.

### Actually run the hardening playbook

```bash
make ansible-hardening
```

Applies all changes from `playbooks/hardening.yml`:
- Disables root SSH login
- Enforces key-only auth
- Sets 15-min idle timeout (PCI-DSS 8.2.8)
- Deploys auditd rules (PCI-DSS req 10.2)
- Disables unnecessary services

### Study secrets anti-patterns

```bash
# Open these side by side in your editor:
open ansible/playbooks/secrets-bad.yml   # what NOT to do
open ansible/playbooks/secrets-good.yml  # corrections

# Actually run the good version
cd ansible && ansible-playbook -i inventory/docker-hosts playbooks/secrets-good.yml -v
```

### Demo ansible-vault encryption

```bash
make ansible-secrets-demo
```

Shows `encrypt_string` output — what encrypted variables look like in group_vars.

Manual practice:
```bash
cd ansible
# Encrypt a single value
echo "tch-practice-vault-pass" > .vault_pass
ansible-vault encrypt_string 'Pg@ssw0rd2024!' --name 'vault_db_password' --vault-password-file .vault_pass

# Create an encrypted file
ansible-vault create group_vars/prod/vault.yml --vault-password-file .vault_pass

# Run playbook with vault password
ansible-playbook -i inventory/docker-hosts playbooks/hardening.yml --vault-password-file ./.vault_pass
```

---

## Day 3 — Multi-Region DR (Reference)

The `terraform/day3-resilience/` directory has complete working Terraform for:
- Route53 health check with 20-second detection (2 × 10s)
- Primary + Secondary failover records (TTL 30s)
- RDS Multi-AZ in us-east-1 + cross-region read replica in us-west-2
- ECS auto-scaling (scale out 60s, scale in 300s cooldown)

```bash
# Validate the DR configurations (resilience is included in validate-good)
make validate-good

# Explore the DR architecture
cd terraform/day3-resilience
terraform init -backend=false
terraform validate

# Read the RTO/RPO targets directly from the config (no apply needed)
grep -A4 '^output' main.tf
```

**Key numbers to memorize:**
| Scenario | Detection | RTO | RPO |
|----------|-----------|-----|-----|
| AZ failure (Multi-AZ RDS) | immediate | ~60s | 0 (sync) |
| Region failure (standard RDS) | ~20s | ~15min | < 30s |
| Region failure (Aurora Global) | ~20s | < 2min | < 1s |

---

## Day 4 — Spot-the-Bug Practice

```bash
make bugs-scan      # run checkov — see what it catches
make bugs-reveal    # show the answer key
```

Manual walkthrough:
```bash
# Read the bugs file
open terraform/day4-bugs/bugs.tf

# For each bug:
#   1. Identify the problem without looking at comments
#   2. Name the PCI-DSS requirement it violates
#   3. Write the fix (mentally or in a scratch file)
#   4. Read the ANSWER comment below the bug
#   5. Run checkov and confirm it catches it

checkov -d terraform/day4-bugs --compact
```

Bug 4 (Ansible) is in `ansible/playbooks/secrets-bad.yml` — not Terraform.

---

## Full Command Reference

```bash
make help              # show all targets

# Setup
make install-tools     # brew install everything (one-time)
make setup             # generate SSH key + build containers (one-time)
make up                # start all 4 services
make down              # stop all services
make status            # check service health

# Day 1 — Terraform
make scan-bad          # checkov+tfsec on bad examples (expect failures)
make scan-good         # checkov+tfsec on good examples (expect clean)
make scan-all          # all directories
make validate-good     # terraform validate (must pass)
make localstack-init   # terraform init
make localstack-plan   # terraform plan
make localstack-apply  # terraform apply (LocalStack)

# Day 2 — Vault
make vault-setup       # configure Vault + Postgres connection
make vault-creds       # request live dynamic credential
make vault-list        # show engines + active leases
make vault-policy-test # test least-privilege policy
make vault-revoke-all  # revoke all credentials

# Day 2 — Ansible
make ansible-ping      # test connectivity
make ansible-check     # dry run (--check --diff)
make ansible-hardening # apply PCI-DSS hardening playbook
make ansible-secrets-demo # demo ansible-vault encryption
make ansible-lint      # lint all playbooks

# Day 4
make bugs-scan         # run scanners on spot-the-bug exercises
make bugs-reveal       # show the answer key
```

---

## Assessment Day Checklist

Before starting the 55-minute assessment:

- [ ] This repo is running (`make up` + `make vault-setup`)
- [ ] `tch_prep_claude0.md` is open in a separate window
- [ ] devops-tch-practice repo is open for code reference
- [ ] Browser tabs: Vault UI (localhost:8200), Terraform docs

During the assessment:

- [ ] For code-review questions: scan in order — **secrets → IAM → encryption → networking → logging**
- [ ] Always cite PCI-DSS requirement number, not just "best practice"
- [ ] For DR questions: state RTO/RPO targets upfront, then walk through the architecture
- [ ] Key phrase: *"In a payment CDE, the blast radius of this misconfiguration is..."*

---

*Created for TCH / Verify assessment — May 2026 | Platform: Ubuntu 24.04 LTS + Docker Engine CE*  
*Reference: `tch_prep_claude0.md` | Assessment deadline: 2026-05-26*
