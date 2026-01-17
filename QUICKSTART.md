# Quick Start Guide

This is the fastest way to get the MSK CDC pipeline running.

## Prerequisites

1. **Install required tools:**
   - [Terraform](https://www.terraform.io/downloads) >= 1.0.0
   - [AWS CLI v2](https://aws.amazon.com/cli/)
   - MySQL client (for database setup)

2. **Configure AWS credentials:**
   ```powershell
   aws configure
   ```

3. **Download connector plugins:**
   - [Debezium MySQL Connector](https://debezium.io/releases/) - Download and save as `terraform/debezium-connector.zip`
   - [Confluent JDBC Sink](https://www.confluent.io/hub/confluentinc/kafka-connect-jdbc) - Download and save as `terraform/jdbc-sink-connector.zip`

## Option 1: Automated Deployment (Recommended for Testing)

Run the quick-start script:

```powershell
cd terraform/scripts
.\quick-start.ps1
```

This will:
1. Deploy all infrastructure (VPC, MSK, Aurora, IAM)
2. Guide you through Aurora configuration
3. Deploy MSK Connect connectors

**Time**: 20-30 minutes

## Option 2: Manual Step-by-Step

### Step 1: Deploy Infrastructure

```powershell
cd terraform

# Initialize Terraform
terraform init

# Review what will be created
terraform plan

# Deploy (takes ~20 minutes)
terraform apply
```

### Step 2: Configure Aurora for CDC

Enable binary logging:

```powershell
# Create parameter group
aws rds create-db-cluster-parameter-group \
  --db-cluster-parameter-group-name aurora-mysql-binlog \
  --db-parameter-group-family aurora-mysql8.0 \
  --description "Aurora MySQL with binary logging"

# Set parameters
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name aurora-mysql-binlog \
  --parameters "ParameterName=binlog_format,ParameterValue=ROW,ApplyMethod=immediate" \
               "ParameterName=binlog_row_image,ParameterValue=FULL,ApplyMethod=immediate"

# Apply to cluster
aws rds modify-db-cluster \
  --db-cluster-identifier aurora-cdc-cluster \
  --db-cluster-parameter-group-name aurora-mysql-binlog \
  --apply-immediately

# Reboot
aws rds failover-db-cluster --db-cluster-identifier aurora-cdc-cluster
```

Create database and user:

```powershell
# Get Aurora endpoint
$AURORA_ENDPOINT = terraform output -raw aurora_endpoint

# Connect
mysql -h $AURORA_ENDPOINT -u admin -p
```

```sql
CREATE DATABASE mydb;
USE mydb;

CREATE TABLE users (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(100),
  email VARCHAR(100),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE USER 'debezium'@'%' IDENTIFIED BY 'YourStrongPassword';
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'debezium'@'%';
FLUSH PRIVILEGES;

INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com');
```

### Step 3: Enable Connector Creation

Edit `terraform/terraform.tfvars` and add:

```hcl
create_connectors = true
debezium_plugin_local_path = "./debezium-connector.zip"
jdbc_plugin_local_path = "./jdbc-sink-connector.zip"
```

Apply changes:

```powershell
terraform apply
```

### Step 4: Deploy Connectors

```powershell
cd scripts

# Generate connector configurations
.\generate-connector-configs.ps1

# Deploy connectors
.\deploy-connectors.ps1
```

## Verify Deployment

### Check connector status:

```powershell
aws kafkaconnect list-connectors --region us-east-1
```

Wait for status to be `RUNNING` (5-10 minutes).

### Test CDC:

Insert data into Aurora:

```sql
INSERT INTO users (name, email) VALUES ('Bob', 'bob@example.com');
```

Check CloudWatch Logs:
- AWS Console → CloudWatch → Log Groups → `/aws/mskconnect/`

If Redshift is enabled, verify data:

```sql
-- Connect to Redshift
SELECT * FROM users;
```

## Cost Estimate

- **Without Redshift** (default): ~$400/month
  - MSK (2 brokers): $300/month
  - Aurora: $100/month

- **With Redshift**: ~$1,200/month
  - Additional $800/month for Redshift

To enable Redshift, set in `terraform.tfvars`:
```hcl
create_redshift = true
```

## Troubleshooting

### Connectors fail to start
- Check CloudWatch Logs: `/aws/mskconnect/<connector-name>`
- Verify Aurora binary logging is enabled
- Check security group rules allow MSK Connect to reach MSK and Aurora

### "No suitable driver" error
- Ensure connector plugin ZIPs include all necessary JAR files
- For JDBC sink, include Redshift JDBC driver

### Terraform apply fails
- Check AWS service quotas
- Verify instance types are available in your region
- Try smaller instance types for testing

## Clean Up

To delete all resources and stop charges:

```powershell
cd terraform
terraform destroy
```

Type `yes` to confirm.

## Next Steps

- Review [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for detailed documentation
- Set up CloudWatch alarms for connector failures
- Configure proper secret management (AWS Secrets Manager)
- Review and tighten IAM policies for production use

## Architecture

```
Aurora MySQL (Source)
       ↓
Debezium Connector (CDC)
       ↓
Amazon MSK (Kafka)
       ↓
JDBC Sink Connector
       ↓
Redshift (Target)
```

## Support Resources

- [AWS MSK Connect Docs](https://docs.aws.amazon.com/msk/latest/developerguide/msk-connect.html)
- [Debezium MySQL Docs](https://debezium.io/documentation/reference/connectors/mysql.html)
- [Confluent JDBC Sink Docs](https://docs.confluent.io/kafka-connect-jdbc/current/)
