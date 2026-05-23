variable "region" {
  description = "AWS region (LocalStack ignores this but terraform requires it)"
  type        = string
  default     = "us-east-1"
}

variable "account_id" {
  description = "Fake account ID for LocalStack resources"
  type        = string
  default     = "000000000000"   # LocalStack uses this fake account ID
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "localstack-practice"
}
