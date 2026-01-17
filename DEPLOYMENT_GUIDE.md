# MSK Workshop - Complete Deployment Guide

This guide provides step-by-step instructions to deploy the entire stack and get the MSK connectors running.

## Prerequisites

### Required Tools
- [Terraform](https://www.terraform.io/downloads) >= 1.0.0
- [AWS CLI v2](https://aws.amazon.com/cli/)
- PowerShell (Windows) or Bash (Linux/Mac)
- Active AWS account with appropriate permissions

### Required AWS Permissions
Your AWS credentials need permissions for:
- VPC, Subnet, Security Group, Internet Gateway, Route Table
- MSK (Kafka) cluster creation
- RDS Aurora cluster creation
- Redshift cluster creation (if enabled)
- IAM role and policy creation
- S3 bucket creation
- MSK Connect custom plugin and connector creation
- CloudWatch Logs

### AWS CLI Configuration
Ensure AWS CLI is configured with your credentials:
```powershell
aws configure
# Enter your AWS Access Key ID, Secret Access Key, and preferred region
```

Verify your configuration:
```powershell
aws sts get-caller-identity
```

## Phase 1: Infrastructure Deployment

### Step 1: Configure Variables

The project has two configuration files:
1. `terraform/terraform.tfvars` - Main configuration (already configured)
2. `terraform/secrets.auto.tfvars` - Sensitive credentials

Check your `terraform/terraform.tfvars` settings:
```powershell
cat terraform/terraform.tfvars
```

Key settings:
- `create_redshift = false` - Set to `true` if you need Redshift (adds ~$800/month)
- `aurora_instance_class = "db.r5.large"` - Adjust for cost vs performance

### Step 2: Review Costs

Before deployment, understand the costs:
- **With Redshift disabled** (current setting): ~$400/month
  - MSK: $300/month (2 brokers)
  - Aurora: $100/month
- **With Redshift enabled**: ~$1,216/month (adds $800 for Redshift)

See [terraform/cost-report.md](terraform/cost-report.md) for details.

### Step 3: Initialize Terraform

```powershell
cd terraform
terraform init
```

Expected output: "Terraform has been successfully initialized!"

### Step 4: Review the Deployment Plan

```powershell
terraform plan
```

This shows what will be created:
- 1 VPC with 2 public and 2 private subnets
- 1 MSK cluster (2 brokers)
- 1 Aurora MySQL cluster (1 instance)
- Security groups and networking
- IAM roles for MSK Connect
- 0 or 1 Redshift cluster (based on `create_redshift` variable)

Review carefully. The plan should show approximately 15-20 resources to create.

### Step 5: Deploy Infrastructure

```powershell
terraform apply
```

Type `yes` when prompted.

**Deployment time**: 15-25 minutes
- MSK cluster: ~15 minutes
- Aurora: ~10 minutes
- Other resources: ~2 minutes

### Step 6: Verify Deployment

After successful deployment, capture the outputs:
```powershell
terraform output
```

You should see:
- `vpc_id` - Your VPC ID
- `msk_bootstrap_brokers` - Kafka broker endpoints (CRITICAL for connectors)
- `aurora_endpoint` - Aurora cluster endpoint
- `redshift_endpoint` - Redshift endpoint (if enabled)

**Save these outputs!** You'll need them for connector configuration.

### Step 7: Enable Aurora Binary Logging

For Debezium CDC to work, Aurora MySQL must have binary logging enabled:

1. Go to AWS Console > RDS > Parameter Groups
2. Create a new DB Cluster Parameter Group for `aurora-mysql8.0`
3. Edit parameters:
   - `binlog_format` = `ROW`
   - `binlog_row_image` = `FULL`
4. Go to your Aurora cluster > Modify
5. Apply the new parameter group
6. Reboot the cluster

Alternatively, using AWS CLI:
```powershell
# Create parameter group
aws rds create-db-cluster-parameter-group `
  --db-cluster-parameter-group-name aurora-mysql-binlog `
  --db-parameter-group-family aurora-mysql8.0 `
  --description "Aurora MySQL with binary logging enabled"

# Modify parameters
aws rds modify-db-cluster-parameter-group `
  --db-cluster-parameter-group-name aurora-mysql-binlog `
  --parameters "ParameterName=binlog_format,ParameterValue=ROW,ApplyMethod=immediate" `
               "ParameterName=binlog_row_image,ParameterValue=FULL,ApplyMethod=immediate"

# Apply to cluster
aws rds modify-db-cluster `
  --db-cluster-identifier aurora-cdc-cluster `
  --db-cluster-parameter-group-name aurora-mysql-binlog `
  --apply-immediately

# Reboot
aws rds failover-db-cluster --db-cluster-identifier aurora-cdc-cluster
```

Wait ~5 minutes for the reboot to complete.

## Phase 2: Connector Deployment

### Step 8: Download Connector Plugins

You need two connector plugin JARs:

**A. Debezium MySQL Connector**
1. Visit: https://debezium.io/releases/
2. Download Debezium MySQL Connector (version 2.4.x or 2.5.x recommended)
3. Extract and create a ZIP containing all JARs

**B. Confluent JDBC Sink Connector**
1. Visit: https://www.confluent.io/hub/confluentinc/kafka-connect-jdbc
2. Download the connector
3. Extract and create a ZIP containing all JARs

Place both ZIP files in the `terraform/` directory:
- `terraform/debezium-connector.zip`
- `terraform/jdbc-sink-connector.zip`

### Step 9: Enable Connector Creation in Terraform

Edit `terraform/terraform.tfvars` and add:
```hcl
create_connectors = true
debezium_plugin_local_path = "./debezium-connector.zip"
jdbc_plugin_local_path = "./jdbc-sink-connector.zip"
```

Apply the configuration:
```powershell
terraform apply
```

This will:
1. Create an S3 bucket for plugins
2. Upload both connector ZIPs
3. Create MSK Connect custom plugins

**Time**: ~5 minutes

Get the plugin ARNs:
```powershell
aws kafkaconnect list-custom-plugins --region us-east-1
```

Save the ARNs - you'll need them shortly.

### Step 10: Create Aurora Database and User

Connect to Aurora and create a database for CDC:

```powershell
# Get Aurora endpoint
$AURORA_ENDPOINT = terraform output -raw aurora_endpoint

# Connect using MySQL client (install if needed)
mysql -h $AURORA_ENDPOINT -u admin -p
```

Run these SQL commands:
```sql
-- Create database
CREATE DATABASE mydb;

-- Create test table
USE mydb;
CREATE TABLE users (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(100),
  email VARCHAR(100),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create replication user for Debezium
CREATE USER 'debezium'@'%' IDENTIFIED BY 'YourStrongPasswordHere';
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'debezium'@'%';
FLUSH PRIVILEGES;

-- Insert test data
INSERT INTO users (name, email) VALUES
  ('Alice Smith', 'alice@example.com'),
  ('Bob Jones', 'bob@example.com');

SELECT * FROM users;
```

### Step 11: Update Connector Configurations

The connector template files need to be updated with your actual infrastructure values.

Run the provided script to generate connector configurations:
```powershell
cd terraform
.\scripts\generate-connector-configs.ps1
```

This will create files in `terraform/connectors/generated/` with:
- Your actual MSK bootstrap brokers
- Your actual Aurora endpoint
- Your actual Redshift endpoint (if enabled)
- Credentials from `secrets.auto.tfvars`

**IMPORTANT**: These generated files contain secrets. Never commit them to git.

### Step 12: Deploy Connectors

Deploy the connectors using the deployment script:

```powershell
cd terraform\scripts

# Deploy connectors
.\deploy-connectors.ps1
```

This script will:
1. Read the generated connector configs
2. Get the custom plugin ARNs
3. Create MSK Connect connectors via AWS CLI
4. Output the connector ARNs

**Time**: Connector creation takes 5-10 minutes

### Step 13: Monitor Connector Status

Check connector status:
```powershell
aws kafkaconnect list-connectors --region us-east-1

# Get details of a specific connector
aws kafkaconnect describe-connector --connector-arn <CONNECTOR_ARN>
```

Wait for both connectors to reach `RUNNING` state.

### Step 14: Verify Data Flow

**Test the CDC pipeline:**

1. Insert data into Aurora:
```sql
mysql -h <AURORA_ENDPOINT> -u admin -p mydb
INSERT INTO users (name, email) VALUES ('Charlie Brown', 'charlie@example.com');
```

2. Verify topic creation in MSK:
```powershell
# You'll need a Kafka client or EC2 instance in the VPC to run kafka-console-consumer
# For now, check connector logs in CloudWatch
```

3. If using Redshift, verify data arrival:
```sql
-- Connect to Redshift and query
SELECT * FROM users;
```

## Troubleshooting

### Infrastructure Issues

**Problem**: Terraform apply fails with "InvalidParameterException"
- **Solution**: Check that your AWS region supports the instance types specified
- Try changing `msk_instance_type` to `kafka.t3.small` for testing

**Problem**: Aurora creation fails
- **Solution**: Check that `aurora-mysql` engine is available in your region
- Verify the `aurora_instance_class` is supported

### Connector Issues

**Problem**: Connector stuck in CREATING state
- **Solution**: Check CloudWatch Logs for the connector
- Verify security groups allow communication between MSK Connect and MSK/Aurora

**Problem**: Debezium connector fails to connect to Aurora
- **Solution**:
  - Verify binary logging is enabled (Step 7)
  - Check that debezium user has correct permissions
  - Verify Aurora endpoint and credentials in connector config

**Problem**: Cannot find plugin ARNs
- **Solution**:
```powershell
aws kafkaconnect list-custom-plugins --region us-east-1 --query 'customPlugins[*].[name,customPluginArn]' --output table
```

**Problem**: Connector fails with "No suitable driver"
- **Solution**: Ensure the JDBC plugin ZIP includes the Redshift JDBC driver JAR

## Cost Management

To minimize costs during testing:

1. **Stop Aurora cluster** when not in use:
```powershell
aws rds stop-db-cluster --db-cluster-identifier aurora-cdc-cluster
```

2. **Delete connectors** when not testing:
```powershell
aws kafkaconnect delete-connector --connector-arn <ARN>
```

3. **Destroy everything**:
```powershell
cd terraform
terraform destroy
```

## Next Steps

After successful deployment:
1. Set up monitoring dashboards in CloudWatch
2. Configure alerts for connector failures
3. Implement proper secret management (AWS Secrets Manager)
4. Review and tighten IAM policies
5. Set up VPC endpoints to reduce data transfer costs
6. Configure backup strategies for Aurora

## Architecture Diagram

```
┌─────────────┐
│   Aurora    │ (Source)
│   MySQL     │
└──────┬──────┘
       │ CDC
       ▼
┌─────────────┐     ┌──────────────┐
│  Debezium   │────>│     MSK      │
│  Connector  │     │   (Kafka)    │
└─────────────┘     └──────┬───────┘
                           │
                           ▼
                    ┌──────────────┐     ┌─────────────┐
                    │     JDBC     │────>│  Redshift   │ (Sink)
                    │  Connector   │     └─────────────┘
                    └──────────────┘
```

## Support

If you encounter issues:
1. Check CloudWatch Logs for detailed error messages
2. Review the [MSK Connect documentation](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect.html)
3. Review the [Debezium MySQL documentation](https://debezium.io/documentation/reference/connectors/mysql.html)
4. Check connector status with `aws kafkaconnect describe-connector`
