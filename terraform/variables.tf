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

variable "kafka_version" {
  description = "Kafka version for MSK (choose a supported value in your region)"
  type        = string
  default     = "3.9.x"
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
  # Use a supported modern node type (e.g. ra3.xlplus). Update as needed for your account/region.
  default = "ra3.xlplus"
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

variable "plugin_bucket_name" {
  description = "S3 bucket name to store connector plugin zips (leave empty to let Terraform generate one)"
  type        = string
  default     = ""
}

variable "debezium_plugin_key" {
  type    = string
  default = "debezium-connector.zip"
}

variable "jdbc_plugin_key" {
  type    = string
  default = "jdbc-sink-connector.zip"
}

variable "debezium_plugin_local_path" {
  description = "Local path to Debezium plugin zip. If empty, Terraform will not try to upload it."
  type        = string
  default     = ""
}

variable "jdbc_plugin_local_path" {
  description = "Local path to JDBC sink plugin zip. If empty, Terraform will not try to upload it."
  type        = string
  default     = ""
}

variable "create_connectors" {
  description = "Whether to create MSK Connect custom plugins and connectors via Terraform"
  type        = bool
  default     = false
}

variable "debezium_plugin_name" {
  type    = string
  default = "debezium-plugin"
}

variable "jdbc_plugin_name" {
  type    = string
  default = "jdbc-sink-plugin"
}

variable "connector_mcu_count" {
  type    = number
  default = 1
}

variable "kafkaconnect_version" {
  description = "MSK Connect version to use for connectors"
  type        = string
  default     = "2.9.0"
}

variable "msk_bootstrap_brokers" {
  description = "Comma-separated MSK bootstrap brokers (injected from terraform output or provided manually)"
  type        = string
  default     = ""
}
