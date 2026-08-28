# terraform/modules/networking/main.tf
# Networking infrastructure module

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.operation_name}-c2-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.operation_name}-igw"
  }
}

# Public Subnets
resource "aws_subnet" "public_redirector" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 102)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.operation_name}-public-redirector-subnet"
    Type = "public"
    Component = "redirector"
  }
}

resource "aws_subnet" "public_vpn" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 101)
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.operation_name}-public-vpn-subnet"
    Type = "public"
    Component = "vpn"
  }
}

# Public Attack Subnet (moved from private to public, third octet 103)
resource "aws_subnet" "public_attack" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 103)
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name      = "${var.operation_name}-public-attack-subnet"
    Type      = "public"
    Component = "attack"
  }
}

# Private Subnets
resource "aws_subnet" "private_c2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.operation_name}-private-c2-subnet"
    Type = "private"
    Component = "c2"
  }
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat_c2" {
  domain = "vpc"
  tags = {
    Name = "${var.operation_name}-nat-eip-c2"
  }
  depends_on = [aws_internet_gateway.main]
}

# NAT Gateways
resource "aws_nat_gateway" "c2" {
  allocation_id = aws_eip.nat_c2.id
  subnet_id     = aws_subnet.public_redirector.id

  tags = {
    Name = "${var.operation_name}-nat-c2"
  }
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.operation_name}-public-rt"
  }
}

resource "aws_route_table" "private_c2" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.c2.id
  }

  tags = {
    Name = "${var.operation_name}-private-c2-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public_redirector" {
  subnet_id      = aws_subnet.public_redirector.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_vpn" {
  subnet_id      = aws_subnet.public_vpn.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_attack" {
  subnet_id      = aws_subnet.public_attack.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_c2" {
  subnet_id      = aws_subnet.private_c2.id
  route_table_id = aws_route_table.private_c2.id
}

# VPC Endpoints
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_c2.id]
  security_group_ids  = [var.vpc_endpoints_security_group_id]
  private_dns_enabled = true

  tags = {
    Name = "${var.operation_name}-ssm-endpoint"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_c2.id]
  security_group_ids  = [var.vpc_endpoints_security_group_id]
  private_dns_enabled = true

  tags = {
    Name = "${var.operation_name}-ssmmessages-endpoint"
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_c2.id]
  security_group_ids  = [var.vpc_endpoints_security_group_id]
  private_dns_enabled = true

  tags = {
    Name = "${var.operation_name}-ec2messages-endpoint"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_c2.id]

  tags = {
    Name = "${var.operation_name}-s3-endpoint"
  }
}

# VPC Flow Logs
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count             = var.enable_vpc_flow_logs ? 1 : 0
  name              = "/aws/vpc/flowlogs/${var.operation_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.operation_name}-vpc-flow-logs"
  }
}

resource "aws_iam_role" "flow_logs_role" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  name  = "${var.operation_name}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.operation_name}-flow-logs-role"
  }
}

resource "aws_iam_role_policy" "flow_logs_policy" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  name  = "${var.operation_name}-flow-logs-policy"
  role  = aws_iam_role.flow_logs_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_flow_log" "vpc_flow_logs" {
  count                = var.enable_vpc_flow_logs ? 1 : 0
  iam_role_arn         = aws_iam_role.flow_logs_role[0].arn
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.main.id
  log_destination_type = "cloud-watch-logs"

  tags = {
    Name = "${var.operation_name}-vpc-flow-logs"
  }

  # Ensure cleanup runs after flow log deletion
  depends_on = [null_resource.flow_log_cleanup]
}

# Cleanup helper: waits for flow log to stop writing, then force-deletes log group
# This runs AFTER flow_log is destroyed (due to depends_on above creating reverse destroy order)
resource "null_resource" "flow_log_cleanup" {
  count = var.enable_vpc_flow_logs ? 1 : 0

  # Store values needed during destroy (can't reference other resources in destroy provisioner)
  triggers = {
    log_group_name = aws_cloudwatch_log_group.vpc_flow_logs[0].name
    region         = var.aws_region
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Waiting 15s for VPC flow log to fully stop writing..."
      sleep 15
      echo "Force-deleting log group ${self.triggers.log_group_name}..."
      aws logs delete-log-group --log-group-name "${self.triggers.log_group_name}" --region "${self.triggers.region}" 2>/dev/null || true
      echo "Cleanup complete."
    EOT
  }

  depends_on = [aws_cloudwatch_log_group.vpc_flow_logs]
} 