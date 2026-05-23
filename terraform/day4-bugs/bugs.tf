# ============================================================
# DAY 4 — SPOT-THE-BUG RAPID-FIRE EXAMPLES
# ============================================================
# Assessment drill: read each block, list ALL bugs before looking at the answers.
# Then run: make bugs-scan   → checkov will find most of them.
# Then run: make bugs-reveal → see the full answer key.
#
# Bug 4 (Ansible) is in ansible/playbooks/secrets-bad.yml
# ============================================================


# ── Bug 1 ───────────────────────────────────────────────────────────────────
# QUESTION: List every security problem in this S3 bucket.
# Hint: think about what "public-read" means for a payment data bucket.

resource "aws_s3_bucket" "payment_data" {
  bucket = "tch-payment-data-prod"
}

# ACL is now a separate resource in newer AWS provider versions
# but checkov still flags it
resource "aws_s3_bucket_acl" "payment_data" {
  bucket = aws_s3_bucket.payment_data.id
  acl    = "public-read"   # BUG: payment data bucket readable by the entire internet
}

# No aws_s3_bucket_server_side_encryption_configuration → BUG: unencrypted
# No aws_s3_bucket_public_access_block                  → BUG: could be made public
# No aws_s3_bucket_versioning                           → BUG: no recovery
# ─────────────────────────────────────────────────────────────────────────────
# ANSWER (after you've identified the bugs):
#   Bug 1a: acl = "public-read" — removes all access control for payment data
#           Fix: remove ACL, add aws_s3_bucket_public_access_block (all true)
#   Bug 1b: No server-side encryption (PCI-DSS 3.4)
#   Bug 1c: No public access block — can be re-enabled by misconfiguration
#   Checkov checks: CKV_AWS_53 (ACL), CKV_AWS_19 (public access block), CKV_AWS_3 (encryption)


# ── Bug 2 ───────────────────────────────────────────────────────────────────
# QUESTION: This Lambda handles payment processing. What's wrong with its IAM role?

resource "aws_iam_role" "payment_lambda" {
  name = "payment-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_exec" {
  role       = aws_iam_role.payment_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"  # BUG: full AWS admin
}
# ─────────────────────────────────────────────────────────────────────────────
# ANSWER:
#   Bug: Lambda has AdministratorAccess — can do anything in the AWS account.
#        PCI-DSS 7.2: "restrict access to system components by business need to know."
#        If this Lambda is compromised, attacker has full account control.
#   Fix: Create a custom policy with ONLY what the Lambda needs:
#        - secretsmanager:GetSecretValue on the specific secret ARN
#        - dynamodb:PutItem / GetItem on the specific table ARN
#        - kms:Decrypt on the specific KMS key ARN
#   Checkov: CKV_AWS_40 — "Ensure IAM policies do not allow full administrative privileges"


# ── Bug 3 ───────────────────────────────────────────────────────────────────
# QUESTION: Count every problem with this RDS configuration. There are exactly 3.

resource "aws_db_instance" "payments_bug3" {
  identifier      = "payments-prod"
  engine          = "postgres"
  instance_class  = "db.t3.medium"
  username        = "admin"
  password        = "SuperSecret456!"
  allocated_storage = 20
  db_name           = "payments"

  skip_final_snapshot     = true    # BUG 1
  deletion_protection     = false   # BUG 2
  backup_retention_period = 0       # BUG 3
}
# ─────────────────────────────────────────────────────────────────────────────
# ANSWER:
#   Bug 3a: skip_final_snapshot = true → destroy leaves NO backup of payment data
#           PCI-DSS 12.3.1: must demonstrate ability to recover data
#   Bug 3b: deletion_protection = false → one `terraform destroy` wipes the database
#           Fix: deletion_protection = true + lifecycle { prevent_destroy = true }
#   Bug 3c: backup_retention_period = 0 → no automated backups at all
#           Fix: backup_retention_period = 7 (7 days minimum for payment platforms)
#   Checkov: CKV_AWS_133 (final snapshot), CKV_AWS_157 (deletion protection), CKV_AWS_161 (backup)
#
# BONUS BUG (assessors love this): password = "SuperSecret456!" — hardcoded in state.
#   Fix: manage_master_user_password = true (AWS manages rotation in Secrets Manager)


# ── Bug 5 ───────────────────────────────────────────────────────────────────
# QUESTION: What is wrong with this Terraform backend configuration?
# (Bug 4 is in Ansible — see ansible/playbooks/secrets-bad.yml)

# Terraform backend blocks cannot be inside resource blocks or modules.
# The BAD example is shown here as a local_file resource for checkov scanning.
# In real assessment: this would appear in the actual backend {} block.

# Simulating the state bucket with the same insecure settings:
resource "aws_s3_bucket" "tf_state_bug5" {
  bucket = "terraform-state"   # BUG: generic name — easily guessable by attacker
}

# No encryption resource → BUG: state stored in plaintext
# (Terraform state for a payment platform contains DB passwords, API keys, private keys)

# No versioning → BUG: can't recover from a bad terraform apply that corrupts state

# No aws_dynamodb_table resource for state locking → BUG: concurrent runs corrupt state

# ─────────────────────────────────────────────────────────────────────────────
# ANSWER:
#   Bug 5a: encrypt = false (default) — state stored in plaintext S3
#           State for a payment platform contains EVERY secret value in plaintext.
#           Fix: encrypt = true, kms_key_id = "arn:aws:kms:..."
#   Bug 5b: No dynamodb_table — two concurrent `terraform apply` runs corrupt state
#           Fix: dynamodb_table = "tch-terraform-locks"
#   Bug 5c: Bucket name "terraform-state" is too generic — enumerable by attacker
#           Fix: include account ID in name: "tch-terraform-state-123456789012"
#   Checkov: CKV_AWS_93, CKV2_AWS_72
