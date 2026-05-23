variable "account_id" {
  description = "AWS account ID"
  type        = string
  default     = "123456789012"
}

variable "primary_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "DR / failover AWS region"
  type        = string
  default     = "us-west-2"
}

variable "rto_minutes" {
  description = "Recovery Time Objective in minutes (target: < 15 for payment APIs)"
  type        = number
  default     = 15
}

variable "rpo_seconds" {
  description = "Recovery Point Objective in seconds (target: < 30 for payment transactions)"
  type        = number
  default     = 30
}

variable "db_username" {
  description = "RDS master username"
  type        = string
  default     = "payments_master"
}
