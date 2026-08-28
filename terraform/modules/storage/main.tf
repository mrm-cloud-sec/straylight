# terraform/modules/storage/main.tf
# Storage infrastructure module

terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Random string for unique bucket naming
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# EFS File System
resource "aws_efs_file_system" "main" {
  creation_token   = "${var.operation_name}-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = var.efs_throughput_mode
  provisioned_throughput_in_mibps = var.efs_throughput_mode == "provisioned" ? var.efs_provisioned_throughput : null
  encrypted = true

  tags = {
    Name = "${var.operation_name}-efs"
  }
}

# EFS Mount Targets
resource "aws_efs_mount_target" "private_c2" {
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = var.private_subnet_ids.c2
  security_groups = [var.efs_security_group_id]
}

resource "aws_efs_mount_target" "public_attack" {
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = var.attack_public_subnet_id
  security_groups = [var.efs_security_group_id]
}

# S3 Bucket for configuration storage
# Note: S3 bucket names must use hyphens (not underscores), so we convert here
resource "aws_s3_bucket" "config" {
  bucket        = "${replace(var.operation_name, "_", "-")}-${random_string.bucket_suffix.result}"
  force_destroy = true

  tags = {
    Name = "${var.operation_name}-bucket"
  }
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudWatch Log Group for Application Logs
resource "aws_cloudwatch_log_group" "application_logs" {
  name              = "/aws/ec2/${var.operation_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.operation_name}-application-logs"
    Environment = var.operation_name
  }
}

# CloudWatch Log Group for Apache access/error logs (shipped by CloudWatch Agent
# on the redirector). Pre-creating this in Terraform ensures `terraform destroy`
# cleans it up instead of leaving orphaned log groups in the account.
resource "aws_cloudwatch_log_group" "apache_logs" {
  name              = "/aws/ec2/${var.operation_name}/apache"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.operation_name}-apache-logs"
    Environment = var.operation_name
  }
}