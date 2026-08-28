# terraform/modules/storage/outputs.tf
# Output values for storage module

output "efs_id" {
  description = "EFS file system ID"
  value       = aws_efs_file_system.main.id
}

output "efs_dns_name" {
  description = "EFS DNS name for mounting"
  value       = aws_efs_file_system.main.dns_name
}

output "s3_bucket_name" {
  description = "S3 bucket name for configuration storage"
  value       = aws_s3_bucket.config.bucket
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.config.arn
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for application logs"
  value       = aws_cloudwatch_log_group.application_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "CloudWatch log group ARN"
  value       = aws_cloudwatch_log_group.application_logs.arn
}

output "apache_log_group_name" {
  description = "CloudWatch log group name for Apache logs"
  value       = aws_cloudwatch_log_group.apache_logs.name
}