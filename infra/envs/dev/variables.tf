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

# SQL Server needs about 2 GB of memory, and a t3.micro has 1 GiB for everything. c7i-flex.large
# has 4 GiB and 2 vCPUs like a t3.medium, which isn't on the free plan's list of instance types.
variable "instance_type" {
  description = "The dev server's instance type"
  type        = string
  default     = "c7i-flex.large"
}
