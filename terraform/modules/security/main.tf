# terraform/modules/security/main.tf
# Security infrastructure module

# Look up Route53 hosted zone for DNS validation permissions
data "aws_route53_zone" "main" {
  count        = var.domain_name != "" ? 1 : 0
  name         = var.domain_name
  private_zone = false
}

data "aws_ec2_managed_prefix_list" "cloudfront_origin" {
  count = var.enable_cloudfront ? 1 : 0
  name  = "com.amazonaws.global.cloudfront.origin-facing"
}

locals {
  route53_zone_id = var.domain_name != "" ? data.aws_route53_zone.main[0].zone_id : ""
}

# Security Groups
resource "aws_security_group" "redirector" {
  name        = "${var.operation_name}-redirector-sg"
  description = "Security group for redirector servers"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.enable_cloudfront ? [] : [1]

    content {
      description = "HTTP from Internet for direct-ingress deployments"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  dynamic "ingress" {
    for_each = var.enable_cloudfront ? [1] : []

    content {
      description     = "HTTPS from CloudFront origin-facing infrastructure"
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront_origin[0].id]
    }
  }

  dynamic "ingress" {
    for_each = var.enable_cloudfront ? [] : [1]

    content {
      description = "HTTPS from Internet for direct-ingress deployments"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  ingress {
    description = "SSH from VPN subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [cidrsubnet(var.vpc_cidr_block, 8, 101)]  # VPN subnet only
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.operation_name}-redirector-sg"
  }
}

resource "aws_security_group" "c2" {
  name        = "${var.operation_name}-c2-sg"
  description = "Security group for C2 servers"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from VPN subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [cidrsubnet(var.vpc_cidr_block, 8, 101)]  # VPN subnet only
  }

  ingress {
    description = "HTTPS from Redirector subnet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [cidrsubnet(var.vpc_cidr_block, 8, 102)]  # Redirector subnet only
  }

  ingress {
    description = "Sliver HTTP C2 from Redirector subnet"
    from_port   = 8888
    to_port     = 8888
    protocol    = "tcp"
    cidr_blocks = [cidrsubnet(var.vpc_cidr_block, 8, 102)]  # Redirector subnet only
  }

  ingress {
    description = "Sliver mTLS listener from VPN subnet"
    from_port   = 4444
    to_port     = 4444
    protocol    = "tcp"
    cidr_blocks = [cidrsubnet(var.vpc_cidr_block, 8, 101)]  # VPN subnet only
  }

  ingress {
    description = "Sliver operator gRPC from VPN subnet"
    from_port   = 31337
    to_port     = 31337
    protocol    = "tcp"
    cidr_blocks = [cidrsubnet(var.vpc_cidr_block, 8, 101)]  # VPN subnet only
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.operation_name}-c2-sg"
  }
}

resource "aws_security_group" "vpn" {
  name        = "${var.operation_name}-vpn-sg"
  description = "Security group for VPN servers"
  vpc_id      = var.vpc_id

  ingress {
    description = "WireGuard VPN access"
    from_port   = 51820
    to_port     = 51820
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.operation_name}-vpn-sg"
  }
}

resource "aws_security_group" "attack" {
  name        = "${var.operation_name}-attack-sg"
  description = "Security group for attack servers"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from VPN subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [cidrsubnet(var.vpc_cidr_block, 8, 101)]  # VPN subnet only
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.operation_name}-attack-sg"
  }
}

resource "aws_security_group" "efs" {
  name        = "${var.operation_name}-efs-sg"
  description = "Security group for EFS"
  vpc_id      = var.vpc_id

  ingress {
    description = "NFS from C2 subnet"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [cidrsubnet(var.vpc_cidr_block, 8, 1)]     # C2 subnet
  }

  ingress {
    description = "NFS from Attack subnet"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [cidrsubnet(var.vpc_cidr_block, 8, 103)]   # Attack subnet (now public, 103)
  }

  ingress {
    description = "NFS from VPN subnet for direct mounting"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [cidrsubnet(var.vpc_cidr_block, 8, 101)]   # VPN subnet
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.operation_name}-efs-sg"
  }
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.operation_name}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.operation_name}-vpc-endpoints-sg"
  }
}

# IAM Role for EC2 SSM
resource "aws_iam_role" "ec2_ssm_role" {
  name = "${var.operation_name}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.operation_name}-ec2-ssm-role"
  }
}

# IAM Policy for S3 Config Bucket Access
resource "aws_iam_role_policy" "s3_config_access" {
  name = "${var.operation_name}-s3-config-access"
  role = aws_iam_role.ec2_ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}

# IAM Policy for Route53 DNS Validation (Let's Encrypt certbot)
resource "aws_iam_role_policy" "route53_dns_validation" {
  count = local.route53_zone_id != "" ? 1 : 0
  name  = "${var.operation_name}-route53-dns-validation"
  role  = aws_iam_role.ec2_ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:GetChange"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ]
        Resource = "arn:aws:route53:::hostedzone/${local.route53_zone_id}"
      }
    ]
  })
}

# IAM Policy for SSM Parameter Store Secrets Access
# Allows EC2 instances to read secrets stored by straylight-deployer
resource "aws_iam_role_policy" "ssm_secrets_access" {
  name = "${var.operation_name}-ssm-secrets-access"
  role = aws_iam_role.ec2_ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/straylight/${var.operation_name}/*"
      }
    ]
  })
}

# IAM Role Policy Attachments
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.operation_name}-ec2-profile"
  role = aws_iam_role.ec2_ssm_role.name

  tags = {
    Name = "${var.operation_name}-ec2-profile"
  }
}
