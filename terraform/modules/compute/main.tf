# terraform/modules/compute/main.tf
# Compute infrastructure module

# Data source for AMI
data "aws_ami" "debian" {
  most_recent = true
  owners      = ["136693071363"] # Debian

  filter {
    name   = "name"
    values = ["debian-12-amd64-*"]
  }

  filter {
    name   = "virtualization-type"  
    values = ["hvm"]
  }
}

# Redirector Instance
resource "aws_instance" "redirector" {
  ami                     = data.aws_ami.debian.id
  instance_type           = var.redirector_instance_type
  subnet_id               = var.public_subnet_ids.redirector
  security_groups         = [var.security_group_ids.redirector]
  iam_instance_profile    = var.iam_instance_profile_name
  disable_api_termination = var.enable_termination_protection
  monitoring              = var.enable_detailed_monitoring
  user_data               = file("${path.root}/ssm-bootstrap.sh")

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size.redirector
    encrypted   = true
  }

  tags = {
    Name = "${var.operation_name}-redirector"
    Type = "redirector"
  }
}

# C2 Instance
resource "aws_instance" "c2" {
  ami                     = data.aws_ami.debian.id
  instance_type           = var.c2_instance_type
  subnet_id               = var.private_subnet_ids.c2
  security_groups         = [var.security_group_ids.c2]
  iam_instance_profile    = var.iam_instance_profile_name
  disable_api_termination = var.enable_termination_protection
  monitoring              = var.enable_detailed_monitoring
  user_data               = file("${path.root}/ssm-bootstrap.sh")

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size.c2
    encrypted   = true
  }

  tags = {
    Name = "${var.operation_name}-c2"
    Type = "c2"
  }
}

# VPN Instance
resource "aws_instance" "vpn" {
  ami                     = data.aws_ami.debian.id
  instance_type           = var.vpn_instance_type
  subnet_id               = var.public_subnet_ids.vpn
  security_groups         = [var.security_group_ids.vpn]
  iam_instance_profile    = var.iam_instance_profile_name
  disable_api_termination = var.enable_termination_protection
  monitoring              = var.enable_detailed_monitoring
  user_data               = file("${path.root}/ssm-bootstrap.sh")

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size.vpn
    encrypted   = true
  }

  tags = {
    Name = "${var.operation_name}-vpn"
    Type = "vpn"
  }
}

# Attack Instance
resource "aws_instance" "attack" {
  ami                     = data.aws_ami.debian.id
  instance_type           = var.attack_instance_type
  subnet_id               = var.public_subnet_ids.attack
  security_groups         = [var.security_group_ids.attack]
  iam_instance_profile    = var.iam_instance_profile_name
  disable_api_termination = var.enable_termination_protection
  monitoring              = var.enable_detailed_monitoring
  user_data               = file("${path.root}/ssm-bootstrap.sh")
  associate_public_ip_address = false

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size.attack
    encrypted   = true
  }

  tags = {
    Name = "${var.operation_name}-attack"
    Type = "attack"
  }
} 

# Allocate and associate a stable Elastic IP to the attack instance
resource "aws_eip" "attack" {
  domain = "vpc"

  tags = {
    Name = "${var.operation_name}-attack-eip"
    Type = "attack"
  }
}

resource "aws_eip_association" "attack" {
  instance_id   = aws_instance.attack.id
  allocation_id = aws_eip.attack.id
}