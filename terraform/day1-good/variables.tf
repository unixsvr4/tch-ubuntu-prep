variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (production, staging)"
  type        = string
  default     = "production"
}

variable "account_id" {
  description = "AWS account ID — used to scope IAM policy resource ARNs"
  type        = string
  default     = "123456789012"   # Replace with real account ID
}

variable "db_username" {
  description = "RDS master username — not admin, not root, service-specific name"
  type        = string
  default     = "payments_master"
}

variable "bastion_cidr" {
  description = "CIDR block of the bastion host subnet — only source allowed for SSH"
  type        = string
  default     = "10.0.1.0/32"   # Single bastion IP in production
}

variable "app_port" {
  description = "Application port for the payment API"
  type        = number
  default     = 8443   # HTTPS
}
