# MSK Workshop - CDC Pipeline with Debezium

Complete infrastructure-as-code solution for deploying a Change Data Capture (CDC) pipeline using Amazon MSK (Managed Streaming for Apache Kafka), Aurora MySQL, and Redshift.

## Architecture

```
┌─────────────┐
│   Aurora    │  Source database with binary logging
│   MySQL     │
└──────┬──────┘
       │ CDC (Change Data Capture)
       ▼
┌─────────────┐     ┌──────────────┐
│  Debezium   │────>│     MSK      │  Managed Kafka cluster
│  Connector  │     │   (Kafka)    │
└─────────────┘     └──────┬───────┘
                           │ Kafka topics
                           ▼
                    ┌──────────────┐     ┌─────────────┐
                    │     JDBC     │────>│  Redshift   │  Data warehouse
                    │  Connector   │     │  (optional) │
                    └──────────────┘     └─────────────┘
```

## Features

- **Complete Infrastructure**: VPC, MSK cluster, Aurora MySQL, optional Redshift, bastion host
- **Automated Deployment**: Scripts for infrastructure and connector deployment
- **Secure Access**: Bastion host with AWS Systems Manager for Aurora/MSK access
- **Cost Optimization**: Toggle features on/off, use smaller instances for dev/test
- **Production Ready**: IAM roles, CloudWatch logging, security groups
- **Easy Configuration**: Template-based connector configs with secret injection

## Quick Start

### Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.0.0
- [AWS CLI v2](https://aws.amazon.com/cli/)
- MySQL client
- AWS account with appropriate permissions

### 1. Clone and Configure

```powershell
git clone <repository-url>
cd msk-workshop

# Configure AWS credentials
aws configure
```

### 2. Download Connector Plugins

Download these connectors and place in `terraform/` directory:

- [Debezium MySQL Connector](https://debezium.io/releases/) → `debezium-connector.zip`
- [Confluent JDBC Sink](https://www.confluent.io/hub/confluentinc/kafka-connect-jdbc) → `jdbc-sink-connector.zip`

### 3. Update Configuration

Edit `terraform/terraform.tfvars`:

```hcl
# Set to false to reduce costs (~$407/mo vs ~$1207/mo)
create_redshift = false

# Bastion host for secure Aurora/MSK access
create_bastion = true

# Enable connector plugin upload
create_connectors = true
debezium_plugin_local_path = "./debezium-connector.zip"
jdbc_plugin_local_path = "./jdbc-sink-connector.zip"
```

### 4. Deploy Everything

**Option A: Automated (Recommended)**

```powershell
cd terraform/scripts
.\quick-start.ps1
```

**Option B: Manual Steps**

See [QUICKSTART.md](QUICKSTART.md) for detailed manual instructions.

### 5. Verify Deployment

```powershell
# Check connector status
aws kafkaconnect list-connectors --region us-east-1

# Troubleshoot if needed
cd terraform/scripts
.\troubleshoot.ps1
```

## Documentation

- **[QUICKSTART.md](QUICKSTART.md)** - Fast deployment guide
- **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)** - Comprehensive step-by-step guide
- **[terraform/cost-report.md](terraform/cost-report.md)** - Cost breakdown and estimates

## Project Structure

```
msk-workshop/
├── README.md                      # This file
├── QUICKSTART.md                  # Quick deployment guide
├── DEPLOYMENT_GUIDE.md            # Detailed deployment guide
├── terraform/
│   ├── main.tf                    # VPC, MSK, Aurora, Redshift
│   ├── mskconnect.tf              # MSK Connect plugins
│   ├── msk_connect_iam.tf         # IAM roles and policies
│   ├── variables.tf               # Input variables
│   ├── outputs.tf                 # Output values
│   ├── providers.tf               # Terraform/AWS provider config
│   ├── terraform.tfvars           # Configuration values
│   ├── secrets.auto.tfvars        # Sensitive credentials (git-ignored)
│   ├── cost-report.md             # Cost analysis
│   ├── connectors/
│   │   ├── debezium-aurora-mysql-source.json    # Source connector template
│   │   ├── redshift-jdbc-sink.json              # Sink connector template
│   │   ├── MSK-Connect-deploy-instructions.md   # Manual deployment guide
│   │   └── generated/             # Generated configs (git-ignored)
│   └── scripts/
│       ├── quick-start.ps1        # Automated deployment
│       ├── generate-connector-configs.ps1       # Create connector configs
│       ├── deploy-connectors.ps1  # Deploy connectors to MSK Connect
│       ├── troubleshoot.ps1       # Diagnostic tool
│       └── cleanup-local.ps1      # Clean up local files
```

## Key Scripts

### Infrastructure Management

```powershell
# Deploy infrastructure
cd terraform
terraform init
terraform apply

# View outputs
terraform output

# Destroy everything
terraform destroy
```

### Connector Management

```powershell
cd terraform/scripts

# Generate connector configurations from Terraform outputs
.\generate-connector-configs.ps1

# Deploy connectors to MSK Connect
.\deploy-connectors.ps1

# Deploy specific connector only
.\deploy-connectors.ps1 -ConnectorType debezium

# Check system status
.\troubleshoot.ps1
```

## Cost Estimates

### Development Configuration (Redshift disabled, bastion enabled)
- **MSK**: ~$300/month (2 x kafka.m5.large brokers)
- **Aurora**: ~$100/month (1 x db.r5.large)
- **Bastion**: ~$7/month (1 x t3.micro)
- **Other**: ~$10/month (CloudWatch, S3)
- **Total**: ~$417/month

### Production Configuration (Redshift enabled, bastion enabled)
- **MSK**: ~$300/month
- **Aurora**: ~$100/month
- **Bastion**: ~$7/month
- **Redshift**: ~$800/month (1 x ra3.xlplus)
- **Other**: ~$15/month
- **Total**: ~$1,222/month

See [terraform/cost-report.md](terraform/cost-report.md) for detailed breakdown.

## Configuration Variables

Key variables in `terraform/terraform.tfvars`:

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region for deployment |
| `create_redshift` | `false` | Enable/disable Redshift cluster |
| `create_bastion` | `false` | Enable/disable bastion host for Aurora/MSK access |
| `bastion_instance_type` | `t3.micro` | Bastion host instance type |
| `msk_instance_type` | `kafka.m5.large` | MSK broker instance type |
| `aurora_instance_class` | `db.r5.large` | Aurora instance size |
| `create_connectors` | `false` | Enable plugin upload and creation |

## Troubleshooting

### Connectors not starting

1. **Check CloudWatch Logs**:
   ```powershell
   # Navigate to AWS Console → CloudWatch → Log Groups
   # Look for: /aws/mskconnect/<connector-name>
   ```

2. **Verify Aurora binary logging**:
   ```sql
   SHOW VARIABLES LIKE 'binlog_format';
   SHOW VARIABLES LIKE 'binlog_row_image';
   ```

3. **Run diagnostics**:
   ```powershell
   cd terraform/scripts
   .\troubleshoot.ps1
   ```

### Common Issues

| Issue | Solution |
|-------|----------|
| Connector stuck in CREATING | Check security groups, verify network connectivity |
| "No suitable driver" error | Ensure JDBC driver JAR is in connector plugin ZIP |
| Debezium connection error | Verify binary logging enabled, check user permissions |
| Plugin upload fails | Check S3 bucket permissions, verify ZIP file format |

## Security Considerations

### For Development
- Current configuration uses basic security suitable for testing
- Credentials stored in `secrets.auto.tfvars` (git-ignored)

### For Production
- Use AWS Secrets Manager for credential management
- Tighten IAM policies (currently use wildcards)
- Enable MSK encryption in transit and at rest
- Implement VPC endpoints to avoid internet traffic
- Enable final snapshots for databases
- Use private subnets with NAT Gateway
- Implement least-privilege security group rules

## Testing the Pipeline

### 1. Insert test data

```sql
mysql -h <AURORA_ENDPOINT> -u admin -p mydb

INSERT INTO users (name, email) VALUES
  ('Alice Johnson', 'alice@example.com'),
  ('Bob Smith', 'bob@example.com');
```

### 2. Verify in Kafka

Topics created by Debezium:
- `aurora.mydb.users` - CDC events for users table
- `schema-changes.aurora` - Schema change events

### 3. Verify in Redshift (if enabled)

```sql
-- Connect to Redshift
SELECT * FROM users;
```

## Monitoring

### CloudWatch Dashboards

View connector metrics:
- Message throughput
- Error rates
- Lag metrics

### Connector Status

```powershell
# List all connectors
aws kafkaconnect list-connectors --region us-east-1

# Get detailed status
aws kafkaconnect describe-connector \
  --connector-arn <CONNECTOR_ARN> \
  --region us-east-1
```

## Cleanup

### Temporary Cleanup (Stop Charges)

```powershell
# Delete connectors (keep infrastructure)
aws kafkaconnect delete-connector --connector-arn <ARN>

# Stop Aurora cluster
aws rds stop-db-cluster --db-cluster-identifier aurora-cdc-cluster
```

### Complete Cleanup

```powershell
cd terraform
terraform destroy
```

Type `yes` to confirm. This removes all resources and stops all charges.

## Contributing

Improvements welcome! Areas for contribution:
- Additional sink connectors (S3, Elasticsearch, etc.)
- Terraform modules for better organization
- CI/CD pipeline integration
- Monitoring dashboards and alarms
- Additional security hardening

## Resources

- [AWS MSK Documentation](https://docs.aws.amazon.com/msk/)
- [Debezium Documentation](https://debezium.io/documentation/)
- [Confluent Kafka Connect](https://docs.confluent.io/platform/current/connect/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## License

This project is provided as-is for educational and workshop purposes.

## Support

For issues or questions:
1. Run the troubleshooting script: `.\terraform\scripts\troubleshoot.ps1`
2. Check CloudWatch Logs for detailed error messages
3. Review the [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for common issues
4. Open an issue in this repository

---

**Note**: This infrastructure incurs AWS charges. Always run `terraform destroy` when finished testing to avoid unexpected costs.
