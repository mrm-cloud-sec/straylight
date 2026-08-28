# terraform/modules/storage/variables.tf
# Input variables for storage module

variable "operation_name" {
  description = "Operation name for resource identification"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for EFS mount targets"
  type = object({
    c2     = string
  })
}

variable "efs_security_group_id" {
  description = "Security group ID for EFS"
  type        = string
}

variable "attack_public_subnet_id" {
  description = "Public subnet ID for Attack server EFS mount target"
  type        = string
}

variable "efs_throughput_mode" {
  description = "EFS throughput mode (provisioned or bursting)"
  type        = string
  default     = "bursting"
}

variable "efs_provisioned_throughput" {
  description = "EFS provisioned throughput in MiB/s (only used if throughput_mode is provisioned)"
  type        = number
  default     = 100
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
} 