output "vpc_id" {
  value = aws_vpc.this.id
}

output "msk_bootstrap_brokers" {
  value = aws_msk_cluster.this.bootstrap_brokers
}

output "aurora_endpoint" {
  value = aws_rds_cluster.aurora.endpoint
}

output "redshift_endpoint" {
  value = var.create_redshift ? aws_redshift_cluster.redshift[0].endpoint : ""
}

output "msk_sg_id" {
  description = "MSK security group ID for connector configuration"
  value       = aws_security_group.msk_sg.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs for connector deployment"
  value       = aws_subnet.private[*].id
}

output "msk_connect_role_arn" {
  description = "IAM role ARN for MSK Connect"
  value       = aws_iam_role.msk_connect_role.arn
}
