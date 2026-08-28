# terraform/modules/compute/variables.tf  
# Input variables for compute module

variable "operation_name" {
  description = "Operation name for resource identification"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs"
  type = object({
    redirector = string
    vpn        = string
    attack     = string
  })
}

variable "private_subnet_ids" {
  description = "Private subnet IDs"
  type = object({
    c2     = string
  })
}

variable "security_group_ids" {
  description = "Security group IDs for instances"
  type = object({
    redirector = string
    c2         = string
    vpn        = string  
    attack     = string
  })
}

variable "iam_instance_profile_name" {
  description = "IAM instance profile name for EC2 instances"
  type        = string
}

variable "redirector_instance_type" {
  description = "EC2 instance type for the redirector server"
  type        = string
}

variable "c2_instance_type" {
  description = "EC2 instance type for the C2 server"
  type        = string
}

variable "vpn_instance_type" {
  description = "EC2 instance type for the VPN server"
  type        = string
}

variable "attack_instance_type" {
  description = "EC2 instance type for the attack server"
  type        = string
}

variable "root_volume_size" {
  description = "Root volume sizes for different server types"
  type = object({
    redirector = number
    c2         = number
    vpn        = number
    attack     = number
  })
}

variable "enable_termination_protection" {
  description = "Enable termination protection for EC2 instances"
  type        = bool
  default     = false
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for EC2 instances"
  type        = bool
  default     = true
} 