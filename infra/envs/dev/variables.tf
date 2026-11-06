variable "region" {
  description = "The AWS region to deploy in"
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "The availability zone for the subnet, inside the region above"
  type        = string
  default     = "us-east-1a"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "subnet_cidr" {
  description = "The CIDR block for the subnet, inside the VPC's block"
  type        = string
  default     = "10.20.1.0/24"
}
