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
  value = aws_redshift_cluster.redshift.endpoint
}
