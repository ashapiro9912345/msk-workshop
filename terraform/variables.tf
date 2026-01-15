variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "List of public subnet CIDRs (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  description = "List of private subnet CIDRs (one per AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "msk_cluster_name" {
  type    = string
  default = "msk-cdc-cluster"
}

variable "msk_instance_type" {
  type    = string
  default = "kafka.m5.large"
}

variable "aurora_cluster_identifier" {
  type    = string
  default = "aurora-cdc-cluster"
}

variable "db_master_username" {
  type    = string
  default = "admin"
}

variable "db_master_password" {
  type      = string
  sensitive = true
}

variable "redshift_cluster_identifier" {
  type    = string
  default = "redshift-cdc-cluster"
}

variable "redshift_node_type" {
  type    = string
  default = "dc2.large"
}

variable "redshift_number_of_nodes" {
  type    = number
  default = 1
}

variable "redshift_master_username" {
  type    = string
  default = "rsadmin"
}

variable "redshift_master_password" {
  type      = string
  sensitive = true
}
