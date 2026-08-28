# terraform/modules/security/outputs.tf
# Output values for security module

output "security_group_ids" {
  description = "Security group IDs"
  value = {
    redirector     = aws_security_group.redirector.id
    c2             = aws_security_group.c2.id
    vpn            = aws_security_group.vpn.id
    attack         = aws_security_group.attack.id
    efs            = aws_security_group.efs.id
    vpc_endpoints  = aws_security_group.vpc_endpoints.id
  }
}

output "iam_role_arn" {
  description = "ARN of the EC2 SSM IAM role"
  value       = aws_iam_role.ec2_ssm_role.arn
}

output "iam_instance_profile_name" {
  description = "Name of the EC2 instance profile"
  value       = aws_iam_instance_profile.ec2_profile.name
}

