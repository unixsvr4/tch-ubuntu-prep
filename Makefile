# tch-ubuntu-prep Makefile
# Usage: cd tch-ubuntu-prep && make <target>    |    make help

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Guard: fail immediately if run from the wrong directory.
# Every target depends on this check running first.
ifeq (,$(wildcard docker-compose.yml))
$(error Run this from inside tch-ubuntu-prep/: cd $(CURDIR) && make $(MAKECMDGOALS))
endif

# Colors via tput (produces real escape bytes -- no literal \033 sequences)
GREEN  := $(shell tput setaf 2 2>/dev/null)
YELLOW := $(shell tput setaf 3 2>/dev/null)
CYAN   := $(shell tput setaf 6 2>/dev/null)
RESET  := $(shell tput sgr0  2>/dev/null)

# Vault / AWS env for local practice
export VAULT_ADDR     ?= http://localhost:8200
export VAULT_TOKEN    ?= root
export AWS_ACCESS_KEY_ID     ?= test
export AWS_SECRET_ACCESS_KEY ?= test
export AWS_DEFAULT_REGION    ?= us-east-1
export TF_PLUGIN_CACHE_DIR   ?= $(HOME)/.terraform.d/plugin-cache
# if /home runs low on space: export TF_PLUGIN_CACHE_DIR=/opt/tf-plugin-cache

# ---------------------------------------------------------------------------
.PHONY: help
help: ## Show all available targets
	@echo ""
	@echo "  $(CYAN)tch-ubuntu-prep -- TCH / Talon Assessment Practice Lab (Ubuntu 24.04)$(RESET)"
	@echo ""
	@echo "  $(YELLOW)SETUP$(RESET)"
	@grep -E '^(setup|install-tools)[^:]*:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*##"}{printf "  make %-28s %s\n", $$1, $$2}'
	@echo ""
	@echo "  $(YELLOW)SERVICES$(RESET)"
	@grep -E '^(up|down|logs|status)[^:]*:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*##"}{printf "  make %-28s %s\n", $$1, $$2}'
	@echo ""
	@echo "  $(YELLOW)DAY 1 -- Terraform Security Scanning$(RESET)"
	@grep -E '^(scan-|validate)[^:]*:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*##"}{printf "  make %-28s %s\n", $$1, $$2}'
	@echo ""
	@echo "  $(YELLOW)DAY 2 -- Vault Dynamic Credentials$(RESET)"
	@grep -E '^vault[^:]*:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*##"}{printf "  make %-28s %s\n", $$1, $$2}'
	@echo ""
	@echo "  $(YELLOW)DAY 2 -- Ansible Hardening$(RESET)"
	@grep -E '^ansible[^:]*:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*##"}{printf "  make %-28s %s\n", $$1, $$2}'
	@echo ""
	@echo "  $(YELLOW)DAY 3 -- LocalStack / Terraform Apply$(RESET)"
	@grep -E '^localstack[^:]*:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*##"}{printf "  make %-28s %s\n", $$1, $$2}'
	@echo ""
	@echo "  $(YELLOW)DAY 4 -- Spot-the-Bug$(RESET)"
	@grep -E '^bugs[^:]*:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*##"}{printf "  make %-28s %s\n", $$1, $$2}'
	@echo ""

# ---------------------------------------------------------------------------
# SETUP
# ---------------------------------------------------------------------------

.PHONY: install-tools
install-tools: ## Install all required tools via apt/pip3 (one-time, Ubuntu 24.04)
	@bash scripts/install-tools.sh

.PHONY: setup
setup: ## Generate demo SSH key, build containers, copy .env (run once before make up)
	@echo "$(CYAN)==> Setting up tch-ubuntu-prep practice lab...$(RESET)"
	@[ -f .env ] || (cp .env.example .env && echo "  Created .env from .env.example")
	@if [ ! -f ansible/demo_key ]; then \
		echo "  Generating demo SSH key for Ansible (DEMO USE ONLY)..."; \
		ssh-keygen -t ed25519 -f ansible/demo_key -N "" -C "tch-ubuntu-prep-demo@local" -q; \
		echo "  $(GREEN)Key generated: ansible/demo_key$(RESET)"; \
	else \
		echo "  Demo key already exists -- skipping"; \
	fi
	@cp ansible/demo_key.pub docker/ansible-target/authorized_keys
	@echo "$(CYAN)==> Building ansible-target container with demo SSH key...$(RESET)"
	@docker compose build ansible-target
	@echo ""
	@echo "$(GREEN)Setup complete. Next step: make up$(RESET)"

# ---------------------------------------------------------------------------
# SERVICES
# ---------------------------------------------------------------------------

.PHONY: up
up: ## Start all services (vault, postgres, localstack, ansible-target)
	@echo "$(CYAN)==> Starting tch-ubuntu-prep services...$(RESET)"
	@docker compose up -d
	@echo ""
	@sleep 5
	@docker compose ps
	@echo ""
	@echo "$(GREEN)Services ready:$(RESET)"
	@echo ""
	@echo "  $(CYAN)Vault$(RESET)      --> Chrome: http://localhost:8200   token: root   (browser UI)"
	@echo "  $(CYAN)LocalStack$(RESET) --> curl http://localhost:4566/_localstack/health  (HTTP API, no browser UI)"
	@echo "  $(CYAN)Postgres$(RESET)   --> psql -h localhost -p 5432 -U vault_admin -d payments  (DB protocol, not HTTP)"
	@echo "  $(CYAN)Ansible$(RESET)    --> ssh -i ansible/demo_key -p 2222 root@localhost  (SSH, not HTTP)"
	@echo ""
	@echo "  Verify all: make status"
	@echo "  Next step:  make vault-setup"

.PHONY: down
down: ## Stop all services and remove containers
	@docker compose down

.PHONY: teardown
teardown: ## FULL CLEANUP: destroy everything after practice is done
	@echo "$(YELLOW)==> Destroying LocalStack Terraform resources...$(RESET)"
	@cd terraform/localstack && terraform destroy -auto-approve -no-color 2>/dev/null || true
	@echo "$(YELLOW)==> Stopping and removing all containers, volumes, and images...$(RESET)"
	@docker compose down --volumes --rmi all --remove-orphans
	@echo "$(YELLOW)==> Removing Terraform state and provider cache...$(RESET)"
	@find terraform/ -name '.terraform' -type d -exec rm -rf {} + 2>/dev/null || true
	@find terraform/ -name 'terraform.tfstate*' -exec rm -f {} + 2>/dev/null || true
	@rm -rf $(HOME)/.terraform.d/plugin-cache
	@echo "$(YELLOW)==> Removing Ansible demo SSH key...$(RESET)"
	@rm -f ansible/demo_key ansible/demo_key.pub docker/ansible-target/authorized_keys
	@echo "$(YELLOW)==> Removing Vault password file if present...$(RESET)"
	@rm -f ansible/.vault_pass
	@echo ""
	@echo "$(GREEN)✓ Teardown complete. Nothing left running.$(RESET)"
	@echo "  To start fresh: make setup && make up && make vault-setup"

.PHONY: logs
logs: ## Follow logs from all services (Ctrl+C to stop)
	@docker compose logs -f

.PHONY: status
status: ## Verify all 4 services are up and responding correctly
	@echo "$(CYAN)==> Container status$(RESET)"
	@docker compose ps
	@echo ""
	@echo "$(CYAN)==> Service health checks$(RESET)"
	@echo ""
	@printf "  %-18s" "Vault (8200):"
	@curl -sf http://localhost:8200/v1/sys/health > /dev/null 2>&1 && \
		echo "$(GREEN)UP$(RESET) -- browser: http://localhost:8200  token: root" || \
		echo "$(YELLOW)DOWN$(RESET) -- run: make up"
	@printf "  %-18s" "LocalStack (4566):"
	@curl -sf http://localhost:4566/_localstack/health > /dev/null 2>&1 && \
		echo "$(GREEN)UP$(RESET) -- curl http://localhost:4566/_localstack/health" || \
		echo "$(YELLOW)DOWN$(RESET) -- run: make up"
	@printf "  %-18s" "Postgres (5432):"
	@docker exec tch-ubuntu-postgres pg_isready -U vault_admin -q 2>/dev/null && \
		echo "$(GREEN)UP$(RESET) -- psql -h localhost -p 5432 -U vault_admin -d payments" || \
		echo "$(YELLOW)DOWN$(RESET) -- run: make up"
	@printf "  %-18s" "Ansible SSH (2222):"
	@ssh -i ansible/demo_key -p 2222 -o ConnectTimeout=3 -o StrictHostKeyChecking=no \
		root@localhost true 2>/dev/null && \
		echo "$(GREEN)UP$(RESET) -- ssh -i ansible/demo_key -p 2222 root@localhost" || \
		echo "$(YELLOW)DOWN$(RESET) -- run: make setup && make up"
	@echo ""

# ---------------------------------------------------------------------------
# DAY 1 -- Terraform Security Scanning
# ---------------------------------------------------------------------------

.PHONY: scan-bad
scan-bad: ## Day 1: Run checkov+tfsec on bad examples -- expect many failures
	@echo "$(CYAN)==> Scanning BAD Terraform examples (expect many failures)...$(RESET)"
	@echo ""
	@echo "$(YELLOW)-- checkov (CIS/PCI-DSS rules) --$(RESET)"
	@checkov -d terraform/day1-bad --compact --quiet 2>/dev/null || true
	@echo ""
	@echo "$(YELLOW)-- tfsec (Terraform-specific rules) --$(RESET)"
	@tfsec terraform/day1-bad --no-color 2>/dev/null || true
	@echo ""
	@echo "$(YELLOW)-- trivy config --$(RESET)"
	@trivy config terraform/day1-bad --quiet 2>/dev/null || true

.PHONY: scan-good
scan-good: ## Day 1: Run checkov+tfsec on good examples -- should be clean
	@echo "$(CYAN)==> Scanning GOOD Terraform examples (expect 0 failures)...$(RESET)"
	@echo ""
	@echo "$(YELLOW)-- checkov --$(RESET)"
	@checkov -d terraform/day1-good --compact --quiet 2>/dev/null || true
	@echo ""
	@echo "$(YELLOW)-- tfsec --$(RESET)"
	@tfsec terraform/day1-good --no-color 2>/dev/null || true

.PHONY: scan-all
scan-all: ## Run all scanners on all Terraform directories
	@bash scripts/scan-all.sh

.PHONY: validate-good
validate-good: ## Run terraform validate on day1-good and day3-resilience (must pass)
	@echo "$(CYAN)==> terraform validate -- day1-good$(RESET)"
	@cd terraform/day1-good && \
		terraform init -backend=false -input=false -no-color > /dev/null 2>&1 && \
		terraform validate -no-color && \
		echo "$(GREEN)day1-good: VALID$(RESET)"
	@echo ""
	@echo "$(CYAN)==> terraform validate -- day3-resilience$(RESET)"
	@cd terraform/day3-resilience && \
		terraform init -backend=false -input=false -no-color > /dev/null 2>&1 && \
		terraform validate -no-color && \
		echo "$(GREEN)day3-resilience: VALID$(RESET)"

.PHONY: validate-fmt
validate-fmt: ## Check terraform formatting across all configs
	@echo "$(CYAN)==> terraform fmt -check -recursive$(RESET)"
	@terraform fmt -check -recursive terraform/ || \
		(echo "Run: terraform fmt -recursive terraform/" && exit 1)
	@echo "$(GREEN)All Terraform files are formatted$(RESET)"

# ---------------------------------------------------------------------------
# DAY 2 -- Vault Dynamic Credentials
# ---------------------------------------------------------------------------

.PHONY: vault-setup
vault-setup: ## Day 2: Configure Vault database engine with dynamic Postgres creds
	@echo "$(CYAN)==> Configuring Vault dynamic database credentials...$(RESET)"
	@bash vault/setup.sh

.PHONY: vault-creds
vault-creds: ## Day 2: Request a live dynamic credential (proves Vault is working)
	@echo "$(CYAN)==> Requesting dynamic credential from Vault...$(RESET)"
	@bash vault/test-creds.sh

.PHONY: vault-list
vault-list: ## Show all enabled secret engines and auth methods in Vault
	@echo "$(YELLOW)-- Secret Engines --$(RESET)"
	@vault secrets list 2>/dev/null || echo "Vault not running (make up)"
	@echo ""
	@echo "$(YELLOW)-- Auth Methods --$(RESET)"
	@vault auth list 2>/dev/null || true
	@echo ""
	@echo "$(YELLOW)-- Active Leases --$(RESET)"
	@vault list sys/leases/lookup/database/creds/payment-role 2>/dev/null || echo "(none)"

.PHONY: vault-revoke-all
vault-revoke-all: ## Revoke ALL active dynamic credential leases
	@echo "$(YELLOW)==> Revoking all dynamic credential leases...$(RESET)"
	@vault lease revoke -prefix database/creds/payment-role 2>/dev/null && \
		echo "$(GREEN)All leases revoked$(RESET)" || echo "No active leases"

.PHONY: vault-policy-test
vault-policy-test: ## Test Vault policy: payment-app can only read its own secrets
	@echo "$(CYAN)==> Testing payment-app policy (least privilege)...$(RESET)"
	@PAYMENT_TOKEN=$$(vault token create -policy=payment-app -ttl=5m -format=json | \
		python3 -c 'import sys,json; print(json.load(sys.stdin)["auth"]["client_token"])') && \
	echo "  Got restricted token (payment-app policy only)" && \
	echo "" && \
	echo "  Allowed: read database/creds/payment-role" && \
	VAULT_TOKEN=$$PAYMENT_TOKEN vault read database/creds/payment-role 2>/dev/null && \
	echo "" && \
	echo "  Denied: list sys/mounts (outside policy)" && \
	VAULT_TOKEN=$$PAYMENT_TOKEN vault list sys/mounts 2>&1 | grep -q "permission denied" && \
	echo "  Permission denied -- least privilege confirmed"

# ---------------------------------------------------------------------------
# DAY 2 -- Ansible Hardening
# ---------------------------------------------------------------------------

.PHONY: ansible-ping
ansible-ping: ## Test Ansible connectivity to the Ubuntu target container
	@cd ansible && ansible all -i inventory/docker-hosts -m ping

.PHONY: ansible-check
ansible-check: ## Day 2: Dry-run hardening playbook (--check --diff, no changes made)
	@echo "$(CYAN)==> ansible-playbook --check --diff (dry run)$(RESET)"
	@cd ansible && ansible-playbook -i inventory/docker-hosts playbooks/hardening.yml --check --diff

.PHONY: ansible-hardening
ansible-hardening: ## Day 2: Run PCI-DSS hardening playbook against Ubuntu target
	@echo "$(CYAN)==> Running hardening playbook against ansible-target...$(RESET)"
	@cd ansible && ansible-playbook -i inventory/docker-hosts playbooks/hardening.yml -v

.PHONY: ansible-secrets-demo
ansible-secrets-demo: ## Day 2: Demo ansible-vault encrypt/decrypt (no_log pattern)
	@echo "$(CYAN)==> Ansible Vault demo$(RESET)"
	@echo ""
	@echo "1. Encrypt a single value (encrypt_string):"
	@echo "   ansible-vault encrypt_string 'MySecret' --name 'db_password' --vault-password-file ansible/.vault_pass"
	@echo ""
	@echo "2. Encrypt a whole file:"
	@echo "   ansible-vault encrypt ansible/group_vars/prod/vault_example.yml"
	@echo ""
	@echo "--- Live demo ---"
	@printf 'tch-ubuntu-demo-vault-pass' > /tmp/vpass && \
		ansible-vault encrypt_string 'Pg@ssw0rd2024!' --name 'db_password' \
		--vault-password-file /tmp/vpass 2>/dev/null && rm -f /tmp/vpass

.PHONY: ansible-lint
ansible-lint: ## Run ansible-lint on all playbooks
	@cd ansible && ansible-lint playbooks/ 2>/dev/null || echo "(install: pip install ansible-lint)"

# ---------------------------------------------------------------------------
# DAY 3 -- LocalStack / Terraform Apply
# ---------------------------------------------------------------------------

.PHONY: localstack-init
localstack-init: ## Init Terraform LocalStack provider (downloads plugins, run once)
	@echo "$(CYAN)==> terraform init (LocalStack)$(RESET)"
	@cd terraform/localstack && terraform init -upgrade -no-color

.PHONY: localstack-plan
localstack-plan: ## Plan secure payment infra against LocalStack (no AWS costs)
	@echo "$(CYAN)==> terraform plan (LocalStack -- no real AWS used)$(RESET)"
	@cd terraform/localstack && terraform plan -no-color

.PHONY: localstack-apply
localstack-apply: ## Apply secure payment infra against LocalStack
	@echo "$(CYAN)==> terraform apply (LocalStack)$(RESET)"
	@cd terraform/localstack && terraform apply -auto-approve -no-color
	@echo ""
	@echo "$(GREEN)Applied. Verify:$(RESET)"
	@echo "  aws --endpoint-url=http://localhost:4566 s3 ls"
	@echo "  aws --endpoint-url=http://localhost:4566 kms list-keys"
	@echo "  aws --endpoint-url=http://localhost:4566 dynamodb list-tables"
	@echo "  aws --endpoint-url=http://localhost:4566 secretsmanager list-secrets"

.PHONY: localstack-destroy
localstack-destroy: ## Destroy all LocalStack resources (reset state)
	@echo "$(YELLOW)==> terraform destroy (LocalStack)$(RESET)"
	@cd terraform/localstack && terraform destroy -auto-approve -no-color

# ---------------------------------------------------------------------------
# DAY 4 -- Spot-the-Bug
# ---------------------------------------------------------------------------

.PHONY: bugs-scan
bugs-scan: ## Day 4: Run checkov on all 5 spot-the-bug examples
	@echo "$(CYAN)==> Scanning day4-bugs/ -- identify every flagged check$(RESET)"
	@echo ""
	@echo "$(YELLOW)-- checkov --$(RESET)"
	@checkov -d terraform/day4-bugs --compact 2>/dev/null || true
	@echo ""
	@echo "$(YELLOW)-- tfsec --$(RESET)"
	@tfsec terraform/day4-bugs --no-color 2>/dev/null || true

.PHONY: bugs-reveal
bugs-reveal: ## Day 4: Show the answer key -- what each bug is and the fix
	@echo ""
	@echo "$(YELLOW)Bug 1 -- S3 bucket with ACL public-read$(RESET)"
	@echo "  CKV: CKV_AWS_19, CKV_AWS_53  |  Fix: aws_s3_bucket_public_access_block"
	@echo ""
	@echo "$(YELLOW)Bug 2 -- Lambda with AdministratorAccess$(RESET)"
	@echo "  CKV: CKV_AWS_40              |  Fix: custom policy, least-privilege only"
	@echo ""
	@echo "$(YELLOW)Bug 3 -- RDS: no backup, no protection, no snapshot$(RESET)"
	@echo "  CKV: CKV_AWS_157, CKV_AWS_161, CKV_AWS_133  |  Fix: see day1-good/main.tf"
	@echo ""
	@echo "$(YELLOW)Bug 4 -- Ansible: password in shell command$(RESET)"
	@echo "  Not a TF issue -- check ansible/playbooks/secrets-bad.yml vs secrets-good.yml"
	@echo ""
	@echo "$(YELLOW)Bug 5 -- Terraform state: no encrypt, no dynamodb lock$(RESET)"
	@echo "  CKV: CKV_AWS_93, CKV2_AWS_72  |  Fix: encrypt=true, dynamodb_table=..."
