# terraform/outputs.tf
# Output values for Ansible integration and infrastructure management

# ============================================================================
# NETWORKING OUTPUTS
# ============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.networking.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = module.networking.private_subnet_ids
}

# ============================================================================
# INSTANCE OUTPUTS
# ============================================================================

output "instance_ids" {
  description = "EC2 instance IDs for all servers"
  value       = module.compute.instance_ids
}

output "instance_private_ips" {
  description = "Private IP addresses of all instances"
  value       = module.compute.instance_private_ips
}

output "instance_public_ips" {
  description = "Public IP addresses where applicable"
  value       = module.compute.instance_public_ips
}

# ============================================================================
# ANSIBLE INVENTORY OUTPUTS
# ============================================================================

output "ansible_inventory" {
  description = "Ansible inventory data in JSON format"
  value = {
    redirector_servers = {
      hosts = {
        (module.compute.instances.redirector.tags.Name) = {
          ansible_host = module.compute.instances.redirector.public_ip
          private_ip   = module.compute.instances.redirector.private_ip
          instance_id  = module.compute.instances.redirector.id
        }
      }
    }
    c2_servers = {
      hosts = {
        (module.compute.instances.c2.tags.Name) = {
          ansible_host = module.compute.instances.c2.private_ip
          private_ip   = module.compute.instances.c2.private_ip
          instance_id  = module.compute.instances.c2.id
        }
      }
    }
    vpn_servers = {
      hosts = {
        (module.compute.instances.vpn.tags.Name) = {
          ansible_host = module.compute.instances.vpn.public_ip
          private_ip   = module.compute.instances.vpn.private_ip
          instance_id  = module.compute.instances.vpn.id
        }
      }
    }
    attack_servers = {
      hosts = {
        (module.compute.instances.attack.tags.Name) = {
          ansible_host = module.compute.instances.attack.public_ip
          private_ip   = module.compute.instances.attack.private_ip
          instance_id  = module.compute.instances.attack.id
        }
      }
    }
  }
}

# ============================================================================
# STORAGE OUTPUTS
# ============================================================================

output "efs_id" {
  description = "EFS file system ID"
  value       = module.storage.efs_id
}

output "efs_dns_name" {
  description = "EFS DNS name for mounting"
  value       = module.storage.efs_dns_name
}

output "s3_bucket_name" {
  description = "S3 bucket name for configuration storage"
  value       = module.storage.s3_bucket_name
}

# ============================================================================
# SECURITY OUTPUTS
# ============================================================================

output "security_group_ids" {
  description = "Security group IDs"
  value       = module.security.security_group_ids
}

# ============================================================================
# CONFIGURATION OUTPUTS
# ============================================================================

output "vpn_configuration" {
  description = "VPN configuration details"
  value = {
    type = var.vpn_type
    port = var.vpn_ports[var.vpn_type].port
    protocol = var.vpn_ports[var.vpn_type].protocol
  }
}

output "c2_configuration" {
  description = "C2 configuration details"
  value = {
    port_range = {
      start = var.custom_c2_ports.start
      end   = var.custom_c2_ports.end
    }
  }
}

# ============================================================================
# LOGGING & COMPLIANCE OUTPUTS
# ============================================================================

output "logging_configuration" {
  description = "Logging and compliance configuration"
  value = {
    vpc_flow_logs_enabled = var.enable_vpc_flow_logs
    log_retention_days    = var.log_retention_days
    detailed_monitoring   = var.enable_detailed_monitoring
    cloudwatch_log_groups = {
      vpc_flow_logs    = var.enable_vpc_flow_logs ? "/aws/vpc/flowlogs/${var.operation_name}" : null
      application_logs = "/aws/ec2/${var.operation_name}"
      apache_logs      = "/aws/ec2/${var.operation_name}/apache"
    }
  }
}

# ============================================================================
# ENVIRONMENT INFO
# ============================================================================

output "operation_info" {
  description = "Operation configuration summary"
  value = {
    operation     = var.operation_name
    aws_region    = var.aws_region
    vpn_type      = var.vpn_type
    compliance_contact = var.compliance_contact
  }
}

output "operation_name" {
  description = "Current operation name"
  value       = var.operation_name
}

# ============================================================================
# CLOUDFRONT / CDN OUTPUTS
# ============================================================================

output "cloudfront_domains" {
  description = "List of CloudFront distribution domain names (*.cloudfront.net)"
  value       = var.enable_cloudfront ? module.cdn[0].cloudfront_domains : []
}

output "cloudfront_distribution_ids" {
  description = "List of CloudFront distribution IDs"
  value       = var.enable_cloudfront ? module.cdn[0].cloudfront_distribution_ids : []
}

output "c2_subdomain" {
  description = "The random subdomain created for this operation"
  value       = var.enable_cloudfront ? module.cdn[0].c2_subdomain : null
}
