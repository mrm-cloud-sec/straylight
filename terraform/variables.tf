# terraform/variables.tf
# Variable definitions for C2 infrastructure

# ============================================================================
# GENERAL CONFIGURATION
# ============================================================================

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "eu-west-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1', 'eu-west-1', etc."
  }
}

variable "operation_name" {
  description = "Operation name for resource identification (e.g., iron_sentinel, silent_bastion, northern_lance)"
  type        = string
  default     = "default_op"

  validation {
    condition     = can(regex("^[a-z0-9_]+$", var.operation_name))
    error_message = "Operation name must contain only lowercase letters, numbers, and underscores (no hyphens)."
  }
}



# ============================================================================
# NETWORKING CONFIGURATION
# ============================================================================

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

# ============================================================================
# EC2 INSTANCE CONFIGURATION
# ============================================================================

variable "redirector_instance_type" {
  description = "EC2 instance type for the redirector server"
  type        = string
  default     = "t3.micro"
  
  validation {
    condition = contains([
      "t3.micro", "t3.small", "t3.medium", "t3.large",
      "t3a.micro", "t3a.small", "t3a.medium", "t3a.large",
      "m5.large", "m5.xlarge", "m5.2xlarge",
      "c5.large", "c5.xlarge", "c5.2xlarge"
    ], var.redirector_instance_type)
    error_message = "Redirector instance type must be a valid EC2 instance type suitable for lightweight workloads."
  }
}

variable "c2_instance_type" {
  description = "EC2 instance type for the C2 server"
  type        = string
  default     = "t3.medium"
  
  validation {
    condition = contains([
      "t3.small", "t3.medium", "t3.large", "t3.xlarge",
      "t3a.small", "t3a.medium", "t3a.large", "t3a.xlarge",
      "m5.large", "m5.xlarge", "m5.2xlarge",
      "c5.large", "c5.xlarge", "c5.2xlarge"
    ], var.c2_instance_type)
    error_message = "C2 instance type must be a valid EC2 instance type suitable for C2 operations."
  }
}

variable "vpn_instance_type" {
  description = "EC2 instance type for the VPN server"
  type        = string
  default     = "t3.micro"
  
  validation {
    condition = contains([
      "t3.micro", "t3.small", "t3.medium", "t3.large",
      "t3a.micro", "t3a.small", "t3a.medium", "t3a.large",
      "m5.large", "m5.xlarge",
      "c5.large", "c5.xlarge"
    ], var.vpn_instance_type)
    error_message = "VPN instance type must be a valid EC2 instance type suitable for VPN operations."
  }
}

variable "attack_instance_type" {
  description = "EC2 instance type for the attack server"
  type        = string
  default     = "t3.micro"
  
  validation {
    condition = contains([
      "t3.micro", "t3.small", "t3.medium", "t3.large", "t3.xlarge", "t3.2xlarge",
      "t3a.micro", "t3a.small", "t3a.medium", "t3a.large", "t3a.xlarge", "t3a.2xlarge",
      "m5.large", "m5.xlarge", "m5.2xlarge", "m5.4xlarge",
      "c5.large", "c5.xlarge", "c5.2xlarge", "c5.4xlarge"
    ], var.attack_instance_type)
    error_message = "Attack instance type must be a valid EC2 instance type suitable for attack operations."
  }
}

# ============================================================================
# STORAGE CONFIGURATION
# ============================================================================

variable "efs_throughput_mode" {
  description = "EFS throughput mode (provisioned or bursting)"
  type        = string
  default     = "bursting"
  
  validation {
    condition = contains(["provisioned", "bursting"], var.efs_throughput_mode)
    error_message = "EFS throughput mode must be either 'provisioned' or 'bursting'."
  }
}

variable "efs_provisioned_throughput" {
  description = "EFS provisioned throughput in MiB/s (only used if throughput_mode is provisioned)"
  type        = number
  default     = 100
  
  validation {
    condition = var.efs_provisioned_throughput >= 1 && var.efs_provisioned_throughput <= 4000
    error_message = "EFS provisioned throughput must be between 1 and 4000 MiB/s."
  }
}

# ============================================================================
# OPTIONAL CONFIGURATIONS
# ============================================================================

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for EC2 instances (required for corporate compliance)"
  type        = bool
  default     = true
}

variable "enable_termination_protection" {
  description = "Enable termination protection for EC2 instances"
  type        = bool
  default     = false
}

variable "root_volume_size" {
  description = "Root volume sizes for different server types"
  type = object({
    redirector = number
    c2         = number
    vpn        = number
    attack     = number
  })
  default = {
    redirector = 20
    c2         = 200
    vpn        = 20
    attack     = 50
  }
  
  validation {
    condition = alltrue([
      var.root_volume_size.redirector >= 8,
      var.root_volume_size.c2 >= 20,
      var.root_volume_size.vpn >= 8,
      var.root_volume_size.attack >= 8
    ])
    error_message = "Root volume sizes must meet minimum requirements: redirector >= 8GB, c2 >= 20GB, vpn >= 8GB, attack >= 8GB."
  }
}

variable "vpn_type" {
  description = "Type of VPN to deploy (wireguard or openvpn)"
  type        = string
  default     = "wireguard"
  
  validation {
    condition = contains(["wireguard", "openvpn"], var.vpn_type)
    error_message = "VPN type must be either 'wireguard' or 'openvpn'."
  }
}

variable "vpn_ports" {
  description = "Port configurations for different VPN types"
  type = object({
    wireguard = object({
      port     = number
      protocol = string
    })
    openvpn = object({
      port     = number
      protocol = string
    })
  })
  default = {
    wireguard = {
      port     = 51820
      protocol = "udp"
    }
    openvpn = {
      port     = 1194
      protocol = "udp"
    }
  }
}

variable "custom_c2_ports" {
  description = "Custom port ranges for C2 communication"
  type = object({
    start = number
    end   = number
  })
  default = {
    start = 8000
    end   = 8010
  }
  
  validation {
    condition = var.custom_c2_ports.start <= var.custom_c2_ports.end
    error_message = "C2 port range start must be less than or equal to end."
  }
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access (empty list disables SSH entirely)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_ssh_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All SSH CIDR blocks must be valid IPv4 CIDR notation."
  }
}

# ============================================================================
# CLOUDFRONT / CDN CONFIGURATION
# ============================================================================

variable "domain_name" {
  description = "Root domain name for C2 subdomains — must be a Route53 hosted zone you control (e.g., example.com)"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*\\.[a-z]{2,}$", var.domain_name))
    error_message = "Domain name must be a valid domain (e.g., example.com)."
  }
}

variable "cloudfront_distribution_count" {
  description = "Number of CloudFront distributions to create for redundancy"
  type        = number
  default     = 10

  validation {
    condition     = var.cloudfront_distribution_count >= 1 && var.cloudfront_distribution_count <= 25
    error_message = "CloudFront distribution count must be between 1 and 25."
  }
}

variable "enable_cloudfront" {
  description = "Enable CloudFront distributions and Route53 subdomain"
  type        = bool
  default     = true
}

variable "cloudfront_price_class" {
  description = "CloudFront price class (PriceClass_100 = US/EU, PriceClass_200 = +Asia, PriceClass_All = Global)"
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "CloudFront price class must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

# ============================================================================
# COMPLIANCE & LOGGING CONFIGURATION
# ============================================================================

variable "log_retention_days" {
  description = "CloudWatch log retention in days for compliance"
  type        = number
  default     = 90
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch retention period."
  }
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs for network monitoring (required for corporate compliance)"
  type        = bool
  default     = true
}

variable "compliance_contact" {
  description = "Contact information for compliance and incident response"
  type        = string
  default     = ""
}

# ============================================================================
# TAGS CONFIGURATION
# ============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "cost_center" {
  description = "Cost center for billing and resource allocation"
  type        = string
  default     = ""
}

variable "owner" {
  description = "Owner of the resources (email or team name)"
  type        = string
  default     = "red-team"
}
