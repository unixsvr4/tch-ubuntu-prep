# ============================================================
# DAY 1 — BAD EXAMPLES  (providers.tf)
# ============================================================
# Purpose: static analysis only (checkov / tfsec / trivy).
# These configs are INTENTIONALLY INSECURE.
#
# Run: make scan-bad
# Expected: many failures — that's the point.
# ============================================================

# BUG (Issue 1): Hardcoded AWS credentials directly in provider block.
# Checkov: CKV_AWS_41 — "Ensure no hard-coded credentials exist in provider"
# PCI-DSS: Req 8.2.2 — do not use group/shared credentials; static keys violate this.
# Fix: remove access_key/secret_key; use IAM role (EC2 instance profile or ECS task role).
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region     = "us-east-1"
  access_key = "AKIAIOSFODNN7EXAMPLE"                    # BUG: hardcoded key in code
  secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" # BUG: hardcoded secret
}
