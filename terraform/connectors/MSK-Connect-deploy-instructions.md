MSK Connect deployment steps (high-level)

This document describes how to deploy the Debezium source connector and a JDBC Redshift sink using MSK Connect. It assumes you already have the MSK cluster and the MSK Connect IAM role created (see `msk_connect_iam.tf`).

1) Build or obtain connector plugin ZIPs
- Debezium MySQL connector and the Kafka Connect JDBC sink typically must be uploaded as a custom plugin bundle (.zip) to S3. Build the plugin jars and zip them according to MSK Connect requirements.

2) Upload plugin to S3
- Upload plugin zip(s) to an S3 bucket in the same region.

Example:

```powershell
aws s3 cp ./debezium-connector.zip s3://my-connector-plugins/debezium-connector.zip
aws s3 cp ./jdbc-sink-connector.zip s3://my-connector-plugins/jdbc-sink-connector.zip
```

3) Create a custom plugin in MSK Connect
- Use `aws mskconnect create-custom-plugin` referencing the S3 bucket+object ARN.

Example:

```powershell
aws mskconnect create-custom-plugin --content S3Location={BucketArn=arn:aws:s3:::my-connector-plugins,FileKey=debezium-connector.zip} --name debezium-plugin --description "Debezium MySQL plugin"
```

4) Create the connector
- Use `aws mskconnect create-connector` and provide:
  - `connectorName`
  - `connectorConfiguration` (map of connector properties)
  - `kafkaCluster` info (VPC connectivity configuration and bootstrap brokers)
  - `serviceExecutionRoleArn` (the role created in `msk_connect_iam.tf`)
  - `plugins` with the custom plugin ARN from step 3

You can use the JSON templates in this repo under `terraform/connectors/` as the connector config payload. Replace placeholders before use:
- `connectors/debezium-aurora-mysql-source.json`
- `connectors/redshift-jdbc-sink.json`

Example CLI (simplified):

```powershell
$plugin_arn="arn:aws:kafkaconnect:region:account:custom-plugin/debezium-plugin-id"
$role_arn="$(aws iam get-role --role-name msk-connect-exec-role --query 'Role.Arn' --output text)"

aws mskconnect create-connector --connector-name my-debezium-connector \
  --kafka-cluster '{"apacheKafka":{"bootstrapServers":"<MSK_BOOTSTRAP>"}}' \
  --capacity '{"provisioned":{"mcuCount":1}}' \
  --connector-configuration file://connectors/debezium-aurora-mysql-source.json \
  --plugins '[{"customPlugin":{"customPluginArn":"'$plugin_arn'"}}]' \
  --service-execution-role-arn $role_arn
```

Notes and troubleshooting
- MSK Connect custom plugin creation can take several minutes.
- Ensure the plugin ZIP includes all required connector JARs and their dependencies.
- For Debezium with Aurora MySQL, enable binary logging and create a replication user with `REPLICATION SLAVE` privileges.
- If using the JDBC sink, ensure the connector has network access to the Redshift cluster (security groups) and the JDBC URL and credentials are correct.
- For production, tighten the IAM policy resources and S3 bucket permissions.

If you want, I can:
- Scaffold the Terraform `aws_mskconnect_connector` resources and S3 plugin upload resources (I will need the plugin S3 path or we can add an S3 bucket and presigned upload step), or
- Generate fully populated connector JSONs with variables filled from the created infra outputs.

Local secret injection helper

Use the script `terraform/scripts/inject-secrets.ps1` to inject secrets from `terraform/secrets.auto.tfvars` into the connector templates and write generated files to `terraform/connectors/generated/`.

Example:

```powershell
cd terraform
.\scripts\inject-secrets.ps1
```

Do NOT commit files in `terraform/connectors/generated/` — they contain secrets.
