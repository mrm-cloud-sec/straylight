# terraform/modules/compute/outputs.tf
# Output values for compute module

output "instance_ids" {
  description = "EC2 instance IDs for all servers"
  value = {
    redirector = aws_instance.redirector.id
    c2         = aws_instance.c2.id
    vpn        = aws_instance.vpn.id
    attack     = aws_instance.attack.id
  }
}

output "instance_private_ips" {
  description = "Private IP addresses of all instances"
  value = {
    redirector = aws_instance.redirector.private_ip
    c2         = aws_instance.c2.private_ip
    vpn        = aws_instance.vpn.private_ip
    attack     = aws_instance.attack.private_ip
  }
}

output "instance_public_ips" {
  description = "Public IP addresses where applicable"  
  value = {
    redirector = aws_instance.redirector.public_ip
    vpn        = aws_instance.vpn.public_ip
    attack     = aws_instance.attack.public_ip
  }
}

output "instances" {
  description = "Complete instance objects for reference"
  value = {
    redirector = aws_instance.redirector
    c2         = aws_instance.c2
    vpn        = aws_instance.vpn
    attack     = aws_instance.attack
  }
} 