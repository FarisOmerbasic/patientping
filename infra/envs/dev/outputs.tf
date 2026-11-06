output "vpc_id" {
  description = "The ID of the dev VPC"
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "The ID of the public subnet, where the server goes"
  value       = aws_subnet.public.id
}

output "security_group_id" {
  description = "The ID of the security group pp-web, which lets in TCP 80"
  value       = aws_security_group.web.id
}
