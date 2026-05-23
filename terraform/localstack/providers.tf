# ============================================================
# LOCALSTACK — Deployable Terraform (no real AWS needed)
# ============================================================
# This is the ONE directory where `terraform apply` actually runs.
# LocalStack emulates S3, KMS, IAM, DynamoDB, SecretsManager locally.
#
# Start LocalStack:   make up
# Initialize:         make localstack-init
# Plan:               make localstack-plan
# Apply:              make localstack-apply
# Verify:             aws --endpoint-url=http://localhost:4566 s3 ls
# Destroy:            make localstack-destroy
# ============================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# LocalStack endpoint — overrides all AWS API calls to hit localhost:4566
provider "aws" {
  region                      = var.region
  access_key                  = "test"    # LocalStack accepts any non-empty key
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  # Required: LocalStack only supports path-style S3 URLs (localhost:4566/bucket),
  # not virtual-hosted-style (bucket.localhost:4566). Without this, aws_s3_bucket hangs forever.
  s3_use_path_style           = true

  # Route ALL service calls through LocalStack
  endpoints {
    s3             = "http://localhost:4566"
    kms            = "http://localhost:4566"
    iam            = "http://localhost:4566"
    dynamodb       = "http://localhost:4566"
    secretsmanager = "http://localhost:4566"
  }
}
