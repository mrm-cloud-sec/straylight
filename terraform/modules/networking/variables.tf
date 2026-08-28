# terraform/modules/networking/variables.tf
# Input variables for networking module

variable "operation_name" {
  description = "Operation name for resource identification"
  type        = string
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "vpc_endpoints_security_group_id" {
  description = "Security group ID for VPC endpoints"
  type        = string
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC flow logs"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
} 