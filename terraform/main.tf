# terraform/main.tf
# Root module calling child modules following Terraform best practices

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge({
      Operation   = var.operation_name
      ManagedBy   = "terraform"
      Owner       = var.owner
      CostCenter  = var.cost_center
    }, var.additional_tags)
  }
}

# ============================================================================
# NETWORKING MODULE
# ============================================================================

module "networking" {
  source = "./modules/networking"

  operation_name                    = var.operation_name
  aws_region                       = var.aws_region
  vpc_cidr                         = var.vpc_cidr
  vpc_endpoints_security_group_id  = module.security.security_group_ids.vpc_endpoints
  enable_vpc_flow_logs             = var.enable_vpc_flow_logs
  log_retention_days               = var.log_retention_days
}

# ============================================================================
# SECURITY MODULE
# ============================================================================

module "security" {
  source = "./modules/security"

  operation_name     = var.operation_name
  vpc_id            = module.networking.vpc_id
  vpc_cidr_block    = module.networking.vpc_cidr_block
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  custom_c2_ports   = var.custom_c2_ports
  vpn_type          = var.vpn_type
  vpn_ports         = var.vpn_ports
  s3_bucket_arn     = module.storage.s3_bucket_arn
  domain_name       = var.enable_cloudfront ? var.domain_name : ""
  enable_cloudfront = var.enable_cloudfront
}

# ============================================================================
# STORAGE MODULE
# ============================================================================

module "storage" {
  source = "./modules/storage"

  operation_name              = var.operation_name
  private_subnet_ids          = {
    c2 = module.networking.private_subnet_ids.c2
  }
  efs_security_group_id       = module.security.security_group_ids.efs
  attack_public_subnet_id     = module.networking.public_subnet_ids.attack
  efs_throughput_mode         = var.efs_throughput_mode
  efs_provisioned_throughput  = var.efs_provisioned_throughput
  log_retention_days          = var.log_retention_days
}

# ============================================================================
# COMPUTE MODULE
# ============================================================================

module "compute" {
  source = "./modules/compute"

  operation_name                 = var.operation_name
  public_subnet_ids             = module.networking.public_subnet_ids
  private_subnet_ids            = {
    c2 = module.networking.private_subnet_ids.c2
  }
  security_group_ids            = {
    redirector = module.security.security_group_ids.redirector
    c2         = module.security.security_group_ids.c2
    vpn        = module.security.security_group_ids.vpn
    attack     = module.security.security_group_ids.attack
  }
  iam_instance_profile_name     = module.security.iam_instance_profile_name
  redirector_instance_type      = var.redirector_instance_type
  c2_instance_type              = var.c2_instance_type
  vpn_instance_type             = var.vpn_instance_type
  attack_instance_type          = var.attack_instance_type
  root_volume_size              = var.root_volume_size
  enable_termination_protection = var.enable_termination_protection
  enable_detailed_monitoring    = var.enable_detailed_monitoring
}

# ============================================================================
# CDN MODULE (CloudFront + Route53)
# ============================================================================

module "cdn" {
  source = "./modules/cdn"
  count  = var.enable_cloudfront ? 1 : 0

  operation_name       = var.operation_name
  domain_name          = var.domain_name
  distribution_count   = var.cloudfront_distribution_count
  redirector_public_ip = module.compute.instance_public_ips.redirector
  price_class          = var.cloudfront_price_class
}
