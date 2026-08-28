# terraform/modules/networking/outputs.tf
# Output values for networking module

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value = {
    redirector = aws_subnet.public_redirector.id
    vpn        = aws_subnet.public_vpn.id
    attack     = aws_subnet.public_attack.id
  }
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value = {
    c2     = aws_subnet.private_c2.id
  }
}

output "nat_gateway_ids" {
  description = "IDs of NAT Gateways"
  value = {
    c2     = aws_nat_gateway.c2.id
  }
}

output "route_table_ids" {
  description = "IDs of route tables"
  value = {
    public      = aws_route_table.public.id
    private_c2  = aws_route_table.private_c2.id
  }
}

output "availability_zones" {
  description = "Availability zones used"
  value       = data.aws_availability_zones.available.names
} 