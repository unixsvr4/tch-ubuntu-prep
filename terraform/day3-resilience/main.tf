# ============================================================
# DAY 3 — MULTI-REGION DR: Route53 Failover + RDS + Auto-Scaling
# ============================================================
# Covers tch_prep_claude0.md sections 3.1 – 3.5
#
# Study scenarios:
#   Q7: "Design Terraform for RTO < 15min, RPO < 30s"
#   Q8: "us-east-1 has a full region failure — walk me through recovery"
#
# Run: make validate-resilience  → must pass
#      make scan-good             → checkov should be clean
# ============================================================


# ── Route53 Health Check + Failover Routing ────────────────────────────────
# Detection time: 2 failed checks × 10s = 20 seconds.
# After detection, Route53 DNS propagation adds ~30-60s (depends on TTL).
# Total failover trigger: ~1 minute.

resource "aws_route53_health_check" "primary" {
  provider = aws.primary

  fqdn              = "payments.us-east-1.tch.internal"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"          # endpoint must return 2xx for check to pass
  failure_threshold = 2                  # 2 consecutive failures → failover (20s detection)
  request_interval  = 10                 # check every 10 seconds

  measure_latency = true                 # capture latency data for monitoring

  tags = { Name = "payments-primary-health-check" }
}

resource "aws_route53_zone" "payments" {
  provider = aws.primary
  name     = "tch.internal"
}

# PRIMARY record — traffic goes here under normal operation
resource "aws_route53_record" "payments_primary" {
  provider = aws.primary

  zone_id = aws_route53_zone.payments.zone_id
  name    = "payments"
  type    = "A"
  ttl     = 30   # Low TTL (30s) = faster DNS propagation during failover

  failover_routing_policy {
    type = "PRIMARY"
  }

  # When this health check fails, Route53 automatically routes to SECONDARY
  health_check_id = aws_route53_health_check.primary.id
  set_identifier  = "primary"
  records         = ["10.10.0.10"]   # Primary region ALB / NLB IP (example)
}

# SECONDARY (DR) record — traffic routes here when primary health check fails
resource "aws_route53_record" "payments_dr" {
  provider = aws.primary

  zone_id = aws_route53_zone.payments.zone_id
  name    = "payments"
  type    = "A"
  ttl     = 30

  failover_routing_policy {
    type = "SECONDARY"
  }

  # No health_check_id on SECONDARY — it's the last resort, always accept traffic
  set_identifier = "secondary"
  records        = ["10.20.0.10"]   # DR region ALB / NLB IP (example)
}


# ── RDS Multi-AZ (Primary) ─────────────────────────────────────────────────
# Multi-AZ: synchronous replication → zero data loss on AZ failure.
# Automatic failover within region: ~60 seconds.
# Cross-region is handled by the read replica below.

resource "aws_db_instance" "payments_primary" {
  provider = aws.primary

  identifier              = "payments-primary"
  engine                  = "postgres"
  engine_version          = "16.2"
  instance_class          = "db.r6g.xlarge"
  allocated_storage       = 500
  storage_type            = "io1"
  iops                    = 3000
  db_name                 = "payments"
  username                = var.db_username
  manage_master_user_password = true

  # HA: multi-AZ = synchronous replication to standby in second AZ
  # Failover within region is automatic and takes ~60 seconds
  multi_az = true

  # Security
  storage_encrypted       = true
  kms_key_id              = aws_kms_key.rds_primary.arn
  publicly_accessible     = false
  deletion_protection     = true

  # Backup — required for cross-region replica and PCI-DSS
  backup_retention_period = 7
  backup_window           = "03:00-04:00"

  # Final snapshot prevents data loss on accidental destroy
  skip_final_snapshot       = false
  final_snapshot_identifier = "payments-primary-final"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_key" "rds_primary" {
  provider                = aws.primary
  description             = "RDS primary encryption key"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  lifecycle { prevent_destroy = true }
}


# ── RDS Cross-Region Read Replica (DR) ────────────────────────────────────
# Asynchronous replication from primary to DR.
# RPO: typically < 30 seconds for payment transaction volumes.
# Promotion to primary: manual step (~5-10 min for standard RDS, < 60s for Aurora Global).
#
# In a real region failure:
#   terraform apply -target=aws_db_instance.payments_dr (promotes replica)
# Or with Aurora Global: automatic promotion in < 60 seconds.

resource "aws_db_instance" "payments_dr" {
  provider = aws.dr

  identifier              = "payments-dr"
  instance_class          = "db.r6g.xlarge"
  storage_encrypted       = true
  kms_key_id              = aws_kms_key.rds_dr.arn

  # This makes it a read replica of the primary
  replicate_source_db = aws_db_instance.payments_primary.identifier

  # DR replica: read-only until promoted; promotion = autonomous primary
  # To promote: terraform apply -replace=aws_db_instance.payments_dr
  # Or: aws rds promote-read-replica --db-instance-identifier payments-dr

  # No backup needed on replica (comes from primary), but keep it ready
  backup_retention_period = 1
  skip_final_snapshot     = false
  final_snapshot_identifier = "payments-dr-promoted-final"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_key" "rds_dr" {
  provider                = aws.dr
  description             = "RDS DR replica encryption key"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  lifecycle { prevent_destroy = true }
}


# ── ECS Auto-Scaling (for zero-downtime deployments) ──────────────────────
# Covers tch_prep_claude0.md section 3.5.
# Scale out fast (60s cooldown) — payment spikes can be sudden.
# Scale in slow (300s cooldown) — avoid thrashing during sustained load.

resource "aws_appautoscaling_target" "payments_ecs" {
  provider = aws.primary

  service_namespace  = "ecs"
  resource_id        = "service/tch-payments-cluster/payments-service"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 3    # Minimum 3 = one per AZ, no single-AZ dependency
  max_capacity       = 50
}

resource "aws_appautoscaling_policy" "payments_cpu" {
  provider = aws.primary

  name               = "payments-cpu-scaling"
  service_namespace  = "ecs"
  resource_id        = aws_appautoscaling_target.payments_ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.payments_ecs.scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    target_value = 60.0   # Scale out when average CPU hits 60%

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    scale_out_cooldown = 60    # Scale out FAST — payment spikes should be served immediately
    scale_in_cooldown  = 300   # Scale in SLOW — don't kill instances mid-request
  }
}


# ── RTO / RPO Reference ────────────────────────────────────────────────────
# These outputs make the architecture targets explicit.
# `terraform output` will display them — useful in assessments.

output "rto_target" {
  value       = "< ${var.rto_minutes} minutes"
  description = "Recovery Time Objective — max downtime for payment APIs"
}

output "rpo_target" {
  value       = "< ${var.rpo_seconds} seconds"
  description = "Recovery Point Objective — max data loss for payment transactions"
}

output "failover_design" {
  value = {
    detection_time    = "20s (2 × 10s Route53 health check intervals)"
    dns_propagation   = "~30s (TTL=30 on failover record)"
    rds_promotion     = "5-10min (standard), < 60s (Aurora Global)"
    total_rto         = "~15min (standard RDS) / ~2min (Aurora Global)"
    replication_lag   = "< 30s async (standard) / < 1s (Aurora Global)"
  }
  description = "Architecture failover timing summary"
}
