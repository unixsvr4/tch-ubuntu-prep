#!/usr/bin/env bash
# ============================================================
# scripts/scan-all.sh — Run all security scanners on all Terraform configs
# ============================================================
# Run: make scan-all
# Output: summary of findings per directory + scanner
# ============================================================
set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

DIRS=(
    "terraform/day1-bad"
    "terraform/day1-good"
    "terraform/day3-resilience"
    "terraform/day4-bugs"
    "terraform/localstack"
)

TOTAL_FAIL=0
TOTAL_PASS=0

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}║  tch-ubuntu-prep Security Scan — All Terraform Configs      ║${RESET}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo "Scanners: checkov | tfsec | trivy config"
echo ""

scan_dir() {
    local dir="$1"
    echo -e "${YELLOW}──────────────────────────────────────────────────────────${RESET}"
    echo -e "${YELLOW}Directory: $dir${RESET}"
    echo ""

    # ── checkov ──────────────────────────────────────────────────────────
    echo "  checkov:"
    if command -v checkov &>/dev/null; then
        CHECKOV_OUT=$(checkov -d "$dir" --compact --quiet 2>/dev/null || true)
        FAILED=$(echo "$CHECKOV_OUT" | grep -c "^FAILED" 2>/dev/null || echo "0")
        PASSED=$(echo "$CHECKOV_OUT" | grep -c "^PASSED" 2>/dev/null || echo "0")
        if [ "$FAILED" -gt 0 ]; then
            echo -e "    ${RED}✗ $FAILED checks failed, $PASSED passed${RESET}"
            echo "$CHECKOV_OUT" | grep "^FAILED" | head -10 | sed 's/^/    /'
            TOTAL_FAIL=$((TOTAL_FAIL + FAILED))
        else
            echo -e "    ${GREEN}✓ $PASSED checks passed, 0 failed${RESET}"
            TOTAL_PASS=$((TOTAL_PASS + PASSED))
        fi
    else
        echo "    (not installed — run: make install-tools)"
    fi

    # ── tfsec ─────────────────────────────────────────────────────────────
    echo ""
    echo "  tfsec:"
    if command -v tfsec &>/dev/null; then
        TFSEC_OUT=$(tfsec "$dir" --no-color --format=text 2>/dev/null || true)
        ISSUES=$(echo "$TFSEC_OUT" | grep -c "Result #" 2>/dev/null || echo "0")
        if [ "$ISSUES" -gt 0 ]; then
            echo -e "    ${RED}✗ $ISSUES issues found${RESET}"
            echo "$TFSEC_OUT" | grep "Result #\|Rule:" | head -10 | sed 's/^/    /'
        else
            echo -e "    ${GREEN}✓ No issues found${RESET}"
        fi
    else
        echo "    (not installed — run: make install-tools)"
    fi

    # ── trivy config ──────────────────────────────────────────────────────
    echo ""
    echo "  trivy config:"
    if command -v trivy &>/dev/null; then
        TRIVY_OUT=$(trivy config "$dir" --quiet --exit-code 0 2>/dev/null || true)
        CRITICAL=$(echo "$TRIVY_OUT" | grep -c "CRITICAL" 2>/dev/null || echo "0")
        HIGH=$(echo "$TRIVY_OUT" | grep -c "HIGH" 2>/dev/null || echo "0")
        if [ "$((CRITICAL + HIGH))" -gt 0 ]; then
            echo -e "    ${RED}✗ CRITICAL: $CRITICAL, HIGH: $HIGH${RESET}"
        else
            echo -e "    ${GREEN}✓ No CRITICAL or HIGH issues${RESET}"
        fi
    else
        echo "    (not installed — run: make install-tools)"
    fi
    echo ""
}

for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        scan_dir "$dir"
    fi
done

echo -e "${CYAN}══════════════════════════════════════════════════════════${RESET}"
echo ""
echo "Expected results:"
echo "  day1-bad:       MANY failures (intentionally insecure)"
echo "  day1-good:      minimal/zero failures (PCI-DSS hardened)"
echo "  day3-resilience: minimal failures (some mock values may trigger)"
echo "  day4-bugs:      failures (spot-the-bug exercises)"
echo "  localstack:     minimal failures (LocalStack-adapted configs)"
echo ""
echo "Study tip: for each failure, ask:"
echo "  1. Which PCI-DSS requirement does this violate?"
echo "  2. What is the blast radius if this misconfiguration is exploited?"
echo "  3. What is the one-line fix?"
echo ""
