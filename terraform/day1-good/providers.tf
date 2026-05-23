# ============================================================
# DAY 1 — GOOD EXAMPLES (providers.tf)
# ============================================================
# GOOD: no hardcoded credentials — uses environment variables or IAM role.
# In production:
#   - EC2/ECS: use instance profile / task role (zero static keys)
#   - CI/CD:   use OIDC federation (GitHub Actions → AWS OIDC provider)
#   - Local:   use AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY env vars
#              or `aws configure` / `aws sso login`

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.region
  # Credentials: from environment (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY)
  # or EC2 instance profile (no static keys in code at all).
  # For local validate without real AWS: set skip_ flags below.
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "terraform"
      Compliance  = "pci-dss"
    }
  }
}

provider "random" {}
