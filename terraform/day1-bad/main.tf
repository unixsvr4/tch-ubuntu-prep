# ============================================================
# DAY 1 — ALL 10 BAD TERRAFORM EXAMPLES
# ============================================================
# PURPOSE: Run `make scan-bad` and see checkov/tfsec flag every issue.
#
# Study method:
#   1. Read each block — identify the problem yourself
#   2. Check tch_prep_claude0.md (Day 1) for the good version + PCI-DSS ref
#   3. Run `make scan-bad` — confirm checkov catches it
#   4. Note the checkov check ID — assessors often ask "how would you detect this in CI?"
# ============================================================


# ── Issue 2: Overly permissive Security Groups ──────────────────────────────
# BUG: 0.0.0.0/0 ingress on all ports — world-readable everything.
# Checkov: CKV_AWS_25 — "Ensure no security groups allow ingress from 0.0.0.0/0 to port 22"
# Checkov: CKV_AWS_24 — "Ensure no security groups allow ingress from 0.0.0.0/0 to port 3389"
# PCI-DSS: Req 1.3 — restrict inbound traffic to only what is necessary.

resource "aws_security_group" "bad_sg" {
  name        = "bad-open-sg"
  description = "EXAMPLE BAD: open to internet on all ports"
  vpc_id      = "vpc-placeholder"   # using default VPC — also bad (Issue 8)
}

resource "aws_security_group_rule" "all_traffic_in" {
  type        = "ingress"
  from_port   = 0
  to_port     = 65535
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]       # BUG: all traffic from anywhere
  security_group_id = aws_security_group.bad_sg.id
}

resource "aws_security_group_rule" "ssh_open" {
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]       # BUG: SSH from the entire internet
  security_group_id = aws_security_group.bad_sg.id
}


# ── Issue 3: Unencrypted S3 Bucket ─────────────────────────────────────────
# BUG: no server-side encryption, no versioning, no public access block, no logging.
# Checkov: CKV_AWS_3   — "Ensure all data stored in the S3 bucket is securely encrypted"
# Checkov: CKV_AWS_21  — "Ensure all data stored in S3 Bucket have versioning enabled"
# Checkov: CKV_AWS_19  — "Ensure the S3 bucket has access control list enabled"
# Checkov: CKV2_AWS_6  — "Ensure that S3 bucket has a Public Access block"
# PCI-DSS: Req 3.4 — encrypt stored cardholder data; Req 10.5 — protect audit logs.

resource "aws_s3_bucket" "payment_logs_bad" {
  bucket = "tch-payment-logs-bad"
  # BUG: no encryption config
  # BUG: no versioning
  # BUG: no public access block (could be made public accidentally)
  # BUG: no access logging (where does bucket-level audit go?)
}


# ── Issue 4: Overly Permissive IAM ─────────────────────────────────────────
# BUG: Action = "*" Resource = "*" — AdministratorAccess equivalent.
# Checkov: CKV_AWS_40  — "Ensure IAM policies are attached only to groups or roles"
# Checkov: CKV_AWS_1   — "Ensure IAM policies that allow full '*:*' administrative privileges are not created"
# PCI-DSS: Req 7.2 — restrict access by business need to know.

resource "aws_iam_policy" "wildcard_policy" {
  name = "bad-wildcard-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "*"            # BUG: full AWS admin — never for a payment app
      Resource = "*"            # BUG: every resource in the account
    }]
  })
}


# ── Issue 5: Unencrypted RDS ────────────────────────────────────────────────
# BUG: no encryption, no Multi-AZ, publicly accessible, no backup, no deletion protection.
# Checkov: CKV_AWS_16  — "Ensure all data stored in the RDS instance is securely encrypted"
# Checkov: CKV_AWS_17  — "Ensure all data stored in the RDS instance has backup"
# Checkov: CKV_AWS_23  — "Ensure the RDS instance is not publicly accessible"
# Checkov: CKV_AWS_157 — "Ensure that RDS instances have deletion protection enabled"
# PCI-DSS: Req 3.4 (encrypt at rest), Req 3.5 (PAN unreadable), Req 4.2.1 (TLS in transit).

resource "aws_db_instance" "payments_bad" {
  identifier          = "payments-bad"
  engine              = "postgres"
  engine_version      = "16.2"
  instance_class      = "db.t3.medium"
  allocated_storage   = 20
  db_name             = "payments"
  username            = "admin"
  password            = "SuperSecret123!"   # BUG: hardcoded password in state
  storage_encrypted   = false               # BUG: data on disk in plaintext
  multi_az            = false               # BUG: no failover — single point of failure
  publicly_accessible = true               # BUG: payment DB reachable from internet
  skip_final_snapshot = true               # BUG: destroy leaves no backup
  deletion_protection = false              # BUG: one `terraform destroy` wipes the DB
  backup_retention_period = 0             # BUG: no automated backups
}


# ── Issue 6: Unencrypted Terraform State ────────────────────────────────────
# NOTE: Backend configs cannot go inside modules (Terraform limitation).
# This is shown as a commented example — the real check is on the backend.tf.
#
# BAD backend (commented because Terraform doesn't allow backend in modules):
#
# terraform {
#   backend "s3" {
#     bucket = "my-tf-state"        # BUG: bucket name too generic (enumerable)
#     key    = "prod/terraform.tfstate"
#     region = "us-east-1"
#     # encrypt = false (default)   BUG: state in plaintext — contains all passwords
#     # no dynamodb_table           BUG: no locking — concurrent runs corrupt state
#   }
# }
#
# Checkov: CKV_AWS_93  — "Ensure S3 bucket used for Terraform state is encrypted"
# Checkov: CKV2_AWS_72 — "Ensure Terraform state is locked via DynamoDB"
#
# Real state backend examples are in terraform/day1-good/backend.tf.example

# Demonstrate the S3 state bucket with bad settings (as a resource, checkov can scan it):
resource "aws_s3_bucket" "terraform_state_bad" {
  bucket = "my-tf-state"   # BUG: generic name, easily guessable
  # BUG: no versioning (can't recover from bad state push)
  # BUG: no encryption
  # BUG: no access logging
}


# ── Issue 8: Default VPC / No Network Segmentation ─────────────────────────
# BUG: using the default VPC — flat network, no isolation between tiers.
# Checkov: CKV2_AWS_12 — "Ensure the default security group of every VPC restricts all traffic"
# PCI-DSS: Req 1.3 — network segmentation required for cardholder data environment.

resource "aws_default_vpc" "bad_default" {
  # BUG: touching the default VPC makes it "managed" but doesn't fix the flat network.
  # Payment workloads must be in a dedicated VPC with separate subnets per tier.
}


# ── Issue 9: EC2 with Public IP and No IMDSv2 ──────────────────────────────
# BUG: public IP assigned, no IMDSv2, no encrypted root volume.
# Checkov: CKV_AWS_79  — "Ensure IMDSv2 is enabled and required on EC2 instances"
# Checkov: CKV_AWS_8   — "Ensure all data stored in the Launch Template is securely encrypted"
# Checkov: CKV_AWS_88  — "Ensure that EC2 instances should not have public IP"
# PCI-DSS: IMDSv2 blocks SSRF attacks from stealing IAM credentials (common attack vector).

resource "aws_instance" "app_bad" {
  ami                         = "ami-0abcdef1234567890"
  instance_type               = "t3.medium"
  associate_public_ip_address = true     # BUG: directly reachable from internet
  # BUG: no metadata_options block — defaults to IMDSv1 which allows SSRF credential theft
  # BUG: no root_block_device with encryption
}


# ── Issue 10: KMS Key Without Rotation ─────────────────────────────────────
# BUG: no key rotation, no deletion window protection, no key policy.
# Checkov: CKV_AWS_7   — "Ensure rotation for customer created CMKs is enabled"
# PCI-DSS: Req 3.7.6 — cryptographic key rotation at defined intervals (annually minimum).

resource "aws_kms_key" "payments_bad" {
  description = "Payment data key"
  # BUG: enable_key_rotation = false (default) — key never rotates
  # BUG: deletion_window_in_days defaults to 30 but isn't explicit
  # BUG: no key policy — relies on account root (overly permissive)
  # BUG: no prevent_destroy lifecycle — accidental `terraform destroy` = permanent data loss
}


# ── Issue 7 (Reference): No CloudTrail ─────────────────────────────────────
# The "bad" version is simply the ABSENCE of CloudTrail — no resource to scan.
# The good version is in day1-good/main.tf.
# PCI-DSS: Req 10.2 — all CDE access must be logged.
# Checkov: No CloudTrail resource → missing coverage for 10.2/10.3/10.5.
# In an assessment: if you see a Terraform repo with no aws_cloudtrail resource,
# that IS the bug. Call it out explicitly: "No CloudTrail = no audit trail = PCI fail."
