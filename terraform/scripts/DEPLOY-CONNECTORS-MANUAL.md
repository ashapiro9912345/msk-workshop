# Manual Connector Deployment - AWS CLI Commands

This guide provides the direct AWS CLI commands to deploy MSK Connect connectors without using PowerShell scripts.

## Prerequisites

1. Aurora database configured with binary logging (Step 2 completed)
2. Database and table created in Aurora
3. MSK Connect custom plugins created by Terraform
4. Generated connector configuration files exist

## Step 1: Verify Prerequisites

```bash
# Check if custom plugins exist
aws kafkaconnect list-custom-plugins --region us-east-1

# Get plugin ARN and revision (save these for later)
aws kafkaconnect list-custom-plugins \
    --region us-east-1 \
    --query "customPlugins[?contains(name, 'debezium')].{name:name,arn:customPluginArn,revision:latestRevision.revision}" \
    --output json

# Get IAM role ARN (save for later)
aws iam get-role \
    --role-name msk-connect-exec-role \
    --query 'Role.Arn' \
    --output text

# Get infrastructure information from Terraform
cd terraform
terraform output -json
```

## Step 2: Set Environment Variables

Run these commands to set up environment variables (makes the next steps easier):

```bash
# From your Terraform outputs
export MSK_BROKERS="b-1.mskcdcclusterdev.dut8cx.c3.kafka.us-east-1.amazonaws.com:9094,b-2.mskcdcclusterdev.dut8cx.c3.kafka.us-east-1.amazonaws.com:9094"
export AURORA_ENDPOINT="aurora-cdc-cluster.cluster-ck5mmcwy82r9.us-east-1.rds.amazonaws.com"
export VPC_ID="vpc-08d5f3c6f961c1024"
export MSK_SG_ID="sg-03744042f7bcde608"
export SUBNET_1="subnet-02e289af3f2b78bb0"
export SUBNET_2="subnet-0256d8fc35608ecb5"
export ROLE_ARN="arn:aws:iam::867344443087:role/msk-connect-exec-role"
export DEBEZIUM_PLUGIN_ARN="arn:aws:kafkaconnect:us-east-1:867344443087:custom-plugin/debezium-plugin/ad28c32e-4ea7-4fc4-9349-ce319a19dd28-2"
export DEBEZIUM_PLUGIN_REVISION="1"
export REGION="us-east-1"

# Database credentials (match what you used in terraform.tfvars and Aurora setup)
export DB_PASSWORD="1zK_F?K+bQC1Rwn_bcXt"
```

**Or use PowerShell (if you prefer):**

```powershell
# From your Terraform outputs
$MSK_BROKERS="b-1.mskcdcclusterdev.dut8cx.c3.kafka.us-east-1.amazonaws.com:9094,b-2.mskcdcclusterdev.dut8cx.c3.kafka.us-east-1.amazonaws.com:9094"
$AURORA_ENDPOINT="aurora-cdc-cluster.cluster-ck5mmcwy82r9.us-east-1.rds.amazonaws.com"
$VPC_ID="vpc-08d5f3c6f961c1024"
$MSK_SG_ID="sg-03744042f7bcde608"
$SUBNET_1="subnet-02e289af3f2b78bb0"
$SUBNET_2="subnet-0256d8fc35608ecb5"
$ROLE_ARN="arn:aws:iam::867344443087:role/msk-connect-exec-role"
$DEBEZIUM_PLUGIN_ARN="arn:aws:kafkaconnect:us-east-1:867344443087:custom-plugin/debezium-plugin/ad28c32e-4ea7-4fc4-9349-ce319a19dd28-2"
$DEBEZIUM_PLUGIN_REVISION="1"
$REGION="us-east-1"
$DB_PASSWORD="1zK_F?K+bQC1Rwn_bcXt"
```

## Step 3: Create CloudWatch Log Group

```bash
aws logs create-log-group \
    --log-group-name /aws/mskconnect/debezium-aurora-mysql-source \
    --region us-east-1
```

## Step 4: Deploy Debezium Connector

### Option A: Using JSON files (cleaner)

Create a temporary file for the connector configuration:

**kafka-cluster.json:**
```json
{
  "apacheKafkaCluster": {
    "bootstrapServers": "b-1.mskcdcclusterdev.dut8cx.c3.kafka.us-east-1.amazonaws.com:9094,b-2.mskcdcclusterdev.dut8cx.c3.kafka.us-east-1.amazonaws.com:9094",
    "vpc": {
      "securityGroups": ["sg-03744042f7bcde608"],
      "subnets": ["subnet-02e289af3f2b78bb0", "subnet-0256d8fc35608ecb5"]
    }
  }
}
```

**capacity.json:**
```json
{
  "provisionedCapacity": {
    "mcuCount": 1,
    "workerCount": 1
  }
}
```

**connector-config.json:**
```json
{
  "connector.class": "io.debezium.connector.mysql.MySqlConnector",
  "tasks.max": "1",
  "database.hostname": "aurora-cdc-cluster.cluster-ck5mmcwy82r9.us-east-1.rds.amazonaws.com",
  "database.port": "3306",
  "database.user": "debezium",
  "database.password": "1zK_F?K+bQC1Rwn_bcXt",
  "database.server.id": "184054",
  "database.server.name": "aurora_mysql_cdc",
  "topic.prefix": "aurora",
  "database.include.list": "mydb",
  "table.include.list": "mydb.users",
  "schema.history.internal.kafka.bootstrap.servers": "b-1.mskcdcclusterdev.dut8cx.c3.kafka.us-east-1.amazonaws.com:9094,b-2.mskcdcclusterdev.dut8cx.c3.kafka.us-east-1.amazonaws.com:9094",
  "schema.history.internal.kafka.topic": "schema-changes.aurora",
  "include.schema.changes": "false",
  "snapshot.mode": "initial",
  "time.precision.mode": "adaptive",
  "decimal.handling.mode": "double",
  "bigint.unsigned.handling.mode": "long"
}
```

**plugins.json:**
```json
[
  {
    "customPlugin": {
      "customPluginArn": "arn:aws:kafkaconnect:us-east-1:867344443087:custom-plugin/debezium-plugin/ad28c32e-4ea7-4fc4-9349-ce319a19dd28-2",
      "revision": 1
    }
  }
]
```

**log-delivery.json:**
```json
{
  "workerLogDelivery": {
    "cloudWatchLogs": {
      "enabled": true,
      "logGroup": "/aws/mskconnect/debezium-aurora-mysql-source"
    }
  }
}
```

Then run:

```bash
aws kafkaconnect create-connector \
    --connector-name debezium-aurora-mysql-source \
    --kafka-cluster file://kafka-cluster.json \
    --capacity file://capacity.json \
    --connector-configuration file://connector-config.json \
    --plugins file://plugins.json \
    --service-execution-role-arn arn:aws:iam::867344443087:role/msk-connect-exec-role \
    --log-delivery file://log-delivery.json \
    --region us-east-1
```

### Option B: Using inline JSON (single command)

```bash
aws kafkaconnect create-connector \
    --connector-name debezium-aurora-mysql-source \
    --kafka-cluster '{"apacheKafkaCluster":{"bootstrapServers":"b-1.mskcdcclusterdev.dut8cx.c3.kafka.us-east-1.amazonaws.com:9094,b-2.mskcdcclusterdev.dut8cx.c3.kafka.us-east-1.amazonaws.com:9094","vpc":{"securityGroups":["sg-03744042f7bcde608"],"subnets":["subnet-02e289af3f2b78bb0","subnet-0256d8fc35608ecb5"]}}}' \
    --capacity '{"provisionedCapacity":{"mcuCount":1,"workerCount":1}}' \
    --connector-configuration '{"connector.class":"io.debezium.connector.mysql.MySqlConnector","tasks.max":"1","database.hostname":"aurora-cdc-cluster.cluster-ck5mmcwy82r9.us-east-1.rds.amazonaws.com","database.port":"3306","database.user":"debezium","database.password":"1zK_F?K+bQC1Rwn_bcXt","database.server.id":"184054","database.server.name":"aurora_mysql_cdc","topic.prefix":"aurora","database.include.list":"mydb","table.include.list":"mydb.users","schema.history.internal.kafka.bootstrap.servers":"b-1.mskcdcclusterdev.dut8cx.c3.kafka.us-east-1.amazonaws.com:9094,b-2.mskcdcclusterdev.dut8cx.c3.kafka.us-east-1.amazonaws.com:9094","schema.history.internal.kafka.topic":"schema-changes.aurora","include.schema.changes":"false","snapshot.mode":"initial","time.precision.mode":"adaptive","decimal.handling.mode":"double","bigint.unsigned.handling.mode":"long"}' \
    --plugins '[{"customPlugin":{"customPluginArn":"arn:aws:kafkaconnect:us-east-1:867344443087:custom-plugin/debezium-plugin/ad28c32e-4ea7-4fc4-9349-ce319a19dd28-2","revision":1}}]' \
    --service-execution-role-arn arn:aws:iam::867344443087:role/msk-connect-exec-role \
    --log-delivery '{"workerLogDelivery":{"cloudWatchLogs":{"enabled":true,"logGroup":"/aws/mskconnect/debezium-aurora-mysql-source"}}}' \
    --region us-east-1
```

## Step 5: Monitor Connector Status

```bash
# List all connectors
aws kafkaconnect list-connectors --region us-east-1

# Get connector ARN from the output above, then describe it
aws kafkaconnect describe-connector \
    --connector-arn <CONNECTOR_ARN> \
    --region us-east-1

# Check connector state specifically
aws kafkaconnect describe-connector \
    --connector-arn <CONNECTOR_ARN> \
    --query 'connectorState' \
    --output text \
    --region us-east-1
```

The connector will go through these states:
- CREATING → RUNNING (success)
- CREATING → FAILED (check logs)

This takes about 5-10 minutes.

## Step 6: View Logs

```bash
# List log streams
aws logs describe-log-streams \
    --log-group-name /aws/mskconnect/debezium-aurora-mysql-source \
    --region us-east-1

# View recent logs
aws logs tail /aws/mskconnect/debezium-aurora-mysql-source \
    --follow \
    --region us-east-1
```

Or use the AWS Console:
- CloudWatch → Log Groups → `/aws/mskconnect/debezium-aurora-mysql-source`

## Step 7: Test CDC

Once the connector is RUNNING, insert test data into Aurora:

```sql
-- From the bastion host, connect to Aurora
mysql -h aurora-cdc-cluster.cluster-ck5mmcwy82r9.us-east-1.rds.amazonaws.com -u admin -p

USE mydb;
INSERT INTO users (name, email) VALUES ('Bob', 'bob@example.com');
INSERT INTO users (name, email) VALUES ('Charlie', 'charlie@example.com');
```

Check the CloudWatch logs to see CDC events being captured.

## Troubleshooting

### Connector fails to create

Check the error message:
```bash
aws kafkaconnect describe-connector \
    --connector-arn <CONNECTOR_ARN> \
    --region us-east-1
```

Common issues:
- **Database connection failed**: Check Aurora security group allows MSK Connect security group
- **Plugin not found**: Verify plugin ARN and revision number
- **IAM permission denied**: Check msk-connect-exec-role has correct permissions

### Connector exists error

If you get "connector already exists", delete it first:

```bash
# List connectors to get ARN
aws kafkaconnect list-connectors --region us-east-1

# Delete the connector
aws kafkaconnect delete-connector \
    --connector-arn <CONNECTOR_ARN> \
    --region us-east-1

# Wait for deletion (check status)
aws kafkaconnect describe-connector \
    --connector-arn <CONNECTOR_ARN> \
    --region us-east-1
```

### Verify Aurora binary logging

From the bastion:
```bash
mysql -h aurora-cdc-cluster.cluster-ck5mmcwy82r9.us-east-1.rds.amazonaws.com -u admin -p

# In MySQL:
SHOW VARIABLES LIKE 'binlog_format';
SHOW VARIABLES LIKE 'binlog_row_image';
```

Both should show the correct values (ROW and FULL).

## Quick Reference

**Get current values from Terraform:**
```bash
cd terraform
terraform output -json | jq -r '
{
  msk_brokers: .msk_bootstrap_brokers.value,
  aurora_endpoint: .aurora_endpoint.value,
  vpc_id: .vpc_id.value,
  msk_sg: .msk_sg_id.value,
  subnets: .private_subnet_ids.value,
  role_arn: .msk_connect_role_arn.value
}'
```

**Get plugin info:**
```bash
aws kafkaconnect list-custom-plugins \
    --region us-east-1 \
    --query "customPlugins[?contains(name, 'debezium')].[name,customPluginArn,latestRevision.revision]" \
    --output table
```

**Check connector status:**
```bash
aws kafkaconnect list-connectors \
    --region us-east-1 \
    --query "connectors[*].[connectorName,connectorState]" \
    --output table
```
