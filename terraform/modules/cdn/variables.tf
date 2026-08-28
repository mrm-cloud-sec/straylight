# terraform/modules/cdn/variables.tf
# Variables for the CDN module

variable "operation_name" {
  description = "Operation name for resource identification"
  type        = string
}

variable "domain_name" {
  description = "Root domain name for the Route53 hosted zone you control (e.g., example.com)"
  type        = string
}

variable "distribution_count" {
  description = "Number of CloudFront distributions to create"
  type        = number
  default     = 10

  validation {
    condition     = var.distribution_count >= 1 && var.distribution_count <= 25
    error_message = "Distribution count must be between 1 and 25."
  }
}

variable "redirector_public_ip" {
  description = "Public IP address of the redirector server"
  type        = string

  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.redirector_public_ip))
    error_message = "Redirector public IP must be a valid IPv4 address."
  }
}

variable "price_class" {
  description = "CloudFront price class (PriceClass_100 = US/EU, PriceClass_200 = +Asia, PriceClass_All = Global)"
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "Price class must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

