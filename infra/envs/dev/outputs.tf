output "vpc_id" {
  description = "The ID of the dev VPC"
  value       = module.network.vpc_id
}

output "subnet_id" {
  description = "The ID of the public subnet, where the server goes"
  value       = module.network.subnet_id
}

output "security_group_id" {
  description = "The ID of the security group pp-web, which lets in TCP 80"
  value       = module.network.security_group_id
}

output "instance_id" {
  description = "The ID of the EC2 instance"
  value       = aws_instance.web.id
}

output "public_ip" {
  description = "The server's public IP address"
  value       = aws_instance.web.public_ip
}
