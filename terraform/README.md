# MSK + Aurora MySQL -> Redshift Terraform scaffold

This folder contains a minimal Terraform scaffold to create the core infrastructure described in the AWS blog: Amazon MSK (Kafka), an Amazon Aurora MySQL cluster (source of CDC), and an Amazon Redshift cluster (target). It intentionally leaves connector configuration and IAM policies as configurable pieces you must complete in your account.

Quickstart

- Edit `terraform/terraform.tfvars` (or pass `-var` values) to set `db_master_password` and `redshift_master_password` and any other variables.
- Initialize and apply:

```powershell
cd terraform
terraform init
terraform apply
```

What this creates
- VPC with public/private subnets (2 AZs)
- MSK cluster (broker nodes in private subnets)
- Aurora MySQL cluster (single writer instance)
- Redshift cluster

Next steps (manual or automated):

- Create IAM roles/policies for MSK Connect (and for any EC2/ECS tasks running Debezium). Attach permissions to write to Redshift or S3 as appropriate.
- Configure Debezium MySQL source connector (Aurora must have binary logging enabled and appropriate user/permissions).
- Configure a Kafka Connect sink: either Confluent/Third-party Redshift sink connector or MSK Connect + Confluent Redshift Sink. Alternatively use Kafka Connect S3 sink + COPY into Redshift.
- Test by inserting/updating records in Aurora and verifying they appear in Redshift.

Notes
- This scaffold is meant as a starting point. Review instance sizes, storage, and production hardening before running in production.
- Clean up with `terraform destroy` when finished.


