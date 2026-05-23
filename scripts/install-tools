#!/usr/bin/env bash
# ============================================================
# scripts/install-tools.sh — Install all required tools
# ============================================================
# Run: make install-tools  (or: sudo bash scripts/install-tools.sh)
# Platform: Ubuntu 24.04 LTS (amd64)
# ============================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

check_or_skip() {
    local tool="$1"
    if command -v "$tool" &>/dev/null; then
        printf "  ${GREEN}✓${RESET} %-20s %s\n" "$tool" "already installed: $(command -v "$tool")"
        return 0
    fi
    return 1
}

echo ""
echo -e "${CYAN}==> tch-ubuntu-prep: Installing all required tools (Ubuntu 24.04 + apt/pip3)${RESET}"
echo ""

# ── 0. Prerequisites ──────────────────────────────────────────────────────
echo "Updating apt and installing prerequisites..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    curl gnupg lsb-release software-properties-common \
    apt-transport-https ca-certificates wget unzip python3-pip

# ── 1. Docker Engine CE ───────────────────────────────────────────────────
echo ""
echo "Docker Engine:"
if ! check_or_skip "docker"; then
    echo -e "  ${YELLOW}→${RESET} Installing Docker Engine CE..."
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"
    printf "  ${GREEN}✓${RESET} %-20s installed\n" "docker"
    echo -e "  ${YELLOW}NOTE:${RESET} Log out and back in (or: newgrp docker) so your user can run docker without sudo"
fi

# ── 2. Terraform + Vault (HashiCorp APT repo) ────────────────────────────
echo ""
echo "Infrastructure tools (HashiCorp APT repo):"

if ! check_or_skip "terraform"; then
    echo -e "  ${YELLOW}→${RESET} Adding HashiCorp APT repo..."
    wget -qO- https://apt.releases.hashicorp.com/gpg \
        | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
        https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
        | sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y terraform vault
    printf "  ${GREEN}✓${RESET} %-20s installed\n" "terraform"
    printf "  ${GREEN}✓${RESET} %-20s installed\n" "vault"
else
    check_or_skip "vault" || { sudo apt-get install -y -qq vault && printf "  ${GREEN}✓${RESET} %-20s installed\n" "vault"; }
fi

# ── 3. Ansible ────────────────────────────────────────────────────────────
echo ""
echo "Ansible:"
if ! check_or_skip "ansible"; then
    echo -e "  ${YELLOW}→${RESET} Installing ansible via apt..."
    sudo apt-get install -y ansible
    printf "  ${GREEN}✓${RESET} %-20s installed\n" "ansible"
fi

# ── 4. Checkov (pip3) ─────────────────────────────────────────────────────
echo ""
echo "Security scanning tools:"
if ! check_or_skip "checkov"; then
    echo -e "  ${YELLOW}→${RESET} Installing checkov via pip3..."
    pip3 install --quiet checkov
    printf "  ${GREEN}✓${RESET} %-20s installed\n" "checkov"
fi

# ── 5. tfsec (binary from GitHub releases) ───────────────────────────────
if ! check_or_skip "tfsec"; then
    echo -e "  ${YELLOW}→${RESET} Installing tfsec..."
    TFSEC_VER=$(curl -s https://api.github.com/repos/aquasecurity/tfsec/releases/latest \
        | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
    curl -sL "https://github.com/aquasecurity/tfsec/releases/download/v${TFSEC_VER}/tfsec-linux-amd64" \
        -o /tmp/tfsec
    sudo install -m 755 /tmp/tfsec /usr/local/bin/tfsec
    rm -f /tmp/tfsec
    printf "  ${GREEN}✓${RESET} %-20s installed (v%s)\n" "tfsec" "$TFSEC_VER"
fi

# ── 6. Trivy (Aqua Security APT repo) ────────────────────────────────────
if ! check_or_skip "trivy"; then
    echo -e "  ${YELLOW}→${RESET} Adding Trivy APT repo..."
    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key \
        | sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg
    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] \
        https://aquasecurity.github.io/trivy-repo/deb generic main" \
        | sudo tee /etc/apt/sources.list.d/trivy.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y trivy
    printf "  ${GREEN}✓${RESET} %-20s installed\n" "trivy"
fi

# ── 7. AWS CLI v2 (official installer) ───────────────────────────────────
echo ""
echo "AWS CLI:"
if ! check_or_skip "aws"; then
    echo -e "  ${YELLOW}→${RESET} Installing AWS CLI v2..."
    curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp
    sudo /tmp/aws/install
    rm -rf /tmp/awscliv2.zip /tmp/aws
    printf "  ${GREEN}✓${RESET} %-20s installed\n" "aws"
fi

# ── Version summary ───────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}==> Installed versions:${RESET}"
printf "  %-20s %s\n" "docker:"     "$(docker --version 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "terraform:"  "$(terraform version -json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("terraform_version","?"))' 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "vault:"      "$(vault version 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "ansible:"    "$(ansible --version 2>/dev/null | head -1 || echo 'not found')"
printf "  %-20s %s\n" "checkov:"    "$(checkov --version 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "tfsec:"      "$(tfsec --version 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "trivy:"      "$(trivy --version 2>/dev/null | head -1 || echo 'not found')"
printf "  %-20s %s\n" "aws cli:"    "$(aws --version 2>/dev/null || echo 'not found')"
echo ""
echo -e "${GREEN}✓ All tools installed. Next: make setup${RESET}"
echo ""
