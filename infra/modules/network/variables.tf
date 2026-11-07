
variable "availability_zone" {
  description = "The availability zone for the subnet"
  type        = string
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
}

variable "subnet_cidr" {
  description = "The CIDR block for the subnet, inside the VPC's block"
  type        = string
}

variable "name" {
  description = "The name of the VPC"
  type        = string
}

