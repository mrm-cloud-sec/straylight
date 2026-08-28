# terraform/modules/security/variables.tf
# Input variables for security module

variable "operation_name" {
  description = "Operation name for resource identification"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where security groups will be created"
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "List of CIDR blocks allowed to SSH"
  type        = list(string)
}

variable "custom_c2_ports" {
  description = "Custom C2 port range"
  type = object({
    start = number
    end   = number
  })
}

variable "vpn_type" {
  description = "Type of VPN to deploy"
  type        = string
}

variable "vpn_ports" {
  description = "Port configurations for different VPN types"
  type = map(object({
    port     = number
    protocol = string
  }))
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 config bucket for EC2 access"
  type        = string
}

variable "domain_name" {
  description = "Domain name for certificate requests (enables Route53 DNS validation permissions)"
  type        = string
  default     = ""
}

variable "enable_cloudfront" {
  description = "Restrict redirector HTTPS ingress to CloudFront origin-facing infrastructure"
  type        = bool
  default     = false
}
