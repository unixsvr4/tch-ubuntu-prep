# ============================================================
# LOCALSTACK — Secure Payment Infra (Actually Deployable)
# ============================================================
# Run: make localstack-apply
# Then verify: aws --endpoint-url=http://localhost:4566 s3 ls
#              aws --endpoint-url=http://localhost:4566 kms list-keys
#              aws --endpoint-url=http://localhost:4566 dynamodb list-tables
#
# This is a simplified version of the good examples in day1-good/
# that can actually apply against LocalStack (some complex resources
# like aws_cloudtrail are not fully supported in LocalStack free tier).
# ============================================================


# ── KMS Keys ──────────────────────────────────────────────────────────────
# LocalStack supports KMS: create keys, use them for S3 encryption.

resource "aws_kms_key" "payments" {
  description             = "Payment data encryption key"
  deletion_window_in_days = 7    # LocalStack: shorter window for easy cleanup
  enable_key_rotation     = true
  tags = { Name = "tch-payments-key", Environment = var.environment }
}

resource "aws_kms_alias" "payments" {
  name          = "alias/tch-payments"
  target_key_id = aws_kms_key.payments.key_id
}

resource "aws_kms_key" "state" {
  description             = "Terraform state encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags = { Name = "tch-state-key" }
}


# ── S3 Buckets (Hardened) ────────────────────────────────────────────────
# LocalStack fully supports: bucket creation, encryption config, versioning, public access block.

# Payment logs bucket — hardened per PCI-DSS 3.4 + 10.5
resource "aws_s3_bucket" "payment_logs" {
  bucket = "tch-payment-logs-${var.account_id}"
  tags   = { Name = "payment-logs", Compliance = "pci-dss" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "payment_logs" {
  bucket = aws_s3_bucket.payment_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.payments.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "payment_logs" {
  bucket = aws_s3_bucket.payment_logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "payment_logs" {
  bucket                  = aws_s3_bucket.payment_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Terraform state bucket — encrypted + versioned
resource "aws_s3_bucket" "terraform_state" {
  bucket = "tch-terraform-state-${var.account_id}"
  tags   = { Name = "terraform-state" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


# ── DynamoDB — Terraform State Lock Table ────────────────────────────────
# Prevents concurrent terraform runs from corrupting state.
# LocalStack fully supports DynamoDB.

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "tch-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = { Name = "terraform-state-locks" }
}


# ── IAM Role (Least Privilege) ────────────────────────────────────────────
# LocalStack supports IAM role and policy creation.

resource "aws_iam_role" "payment_app" {
  name = "payment-app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Name = "payment-app-role", Compliance = "pci-dss-7.2" }
}

resource "aws_iam_policy" "payment_app" {
  name = "payment-app-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:tch/payments/*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.payments.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "payment_app" {
  role       = aws_iam_role.payment_app.name
  policy_arn = aws_iam_policy.payment_app.arn
}


# ── Secrets Manager — Store API Keys ─────────────────────────────────────
# LocalStack supports Secrets Manager.
# In production: use manage_master_user_password for RDS (let AWS rotate).
# For static API keys: store here and rotate via Lambda.

resource "aws_secretsmanager_secret" "stripe_api_key" {
  name        = "tch/payments/stripe-api-key"
  description = "Stripe payment processor API key"
  kms_key_id  = aws_kms_key.payments.arn

  # Rotation: in production, wire this to a Lambda rotation function
  # rotation_lambda_arn = aws_lambda_function.secret_rotation.arn
  # rotation_rules { automatically_after_days = 90 }  # PCI-DSS 8.3.9: rotate every 90 days

  tags = { Name = "stripe-api-key", Compliance = "pci-dss-8.3.9" }
}

resource "aws_secretsmanager_secret_version" "stripe_api_key" {
  secret_id     = aws_secretsmanager_secret.stripe_api_key.id
  secret_string = jsonencode({
    api_key = "sk_live_EXAMPLE_REPLACE_WITH_REAL_KEY"
    # In production: populated by rotation Lambda or external tool, not Terraform
  })

  lifecycle {
    ignore_changes = [secret_string]   # Don't reset the key on every terraform apply
  }
}


# ── Outputs ───────────────────────────────────────────────────────────────

output "payment_bucket" {
  value       = aws_s3_bucket.payment_logs.bucket
  description = "Payment logs S3 bucket name"
}

output "state_bucket" {
  value       = aws_s3_bucket.terraform_state.bucket
  description = "Terraform state S3 bucket name"
}

output "lock_table" {
  value       = aws_dynamodb_table.terraform_locks.name
  description = "DynamoDB state lock table"
}

output "kms_payments_key_id" {
  value       = aws_kms_key.payments.key_id
  description = "Payment data KMS key ID"
}

output "verify_commands" {
  value = <<-EOT
    # Verify resources in LocalStack:
    aws --endpoint-url=http://localhost:4566 s3 ls
    aws --endpoint-url=http://localhost:4566 kms list-keys
    aws --endpoint-url=http://localhost:4566 dynamodb list-tables
    aws --endpoint-url=http://localhost:4566 secretsmanager list-secrets
  EOT
  description = "Commands to verify deployed resources"
}
