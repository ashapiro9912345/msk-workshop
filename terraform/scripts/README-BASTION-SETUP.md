# Running Scripts on the Bastion Host

This guide explains how to copy files to the EC2 bastion host and execute them.

## Method 1: Using AWS Systems Manager Session Manager (Recommended)

### Step 1: Connect to the Bastion

```bash
# Get the bastion instance ID from Terraform
cd terraform
BASTION_ID=$(terraform output -raw bastion_instance_id)

# Start an SSM session
aws ssm start-session --target $BASTION_ID --region us-east-1
```

### Step 2: Copy the Script to Bastion

Open a **new terminal window** (keep the SSM session open) and use this method:

#### Option A: Using S3 as intermediate storage (Easiest)

```bash
# In your local terminal (not the SSM session)
cd terraform/scripts

# Upload script to S3 (use your own bucket or create a temporary one)
aws s3 cp configure-aurora-binlog.sh s3://your-bucket-name/configure-aurora-binlog.sh

# In the SSM session on bastion:
aws s3 cp s3://your-bucket-name/configure-aurora-binlog.sh ~/configure-aurora-binlog.sh
chmod +x ~/configure-aurora-binlog.sh
```

#### Option B: Copy-paste the script content

```bash
# In the SSM session on bastion:
cat > ~/configure-aurora-binlog.sh << 'EOF'
# Paste the entire contents of configure-aurora-binlog.sh here
EOF

chmod +x ~/configure-aurora-binlog.sh
```

### Step 3: Execute the Script

```bash
# In the SSM session on bastion:
cd ~
./configure-aurora-binlog.sh
```

---

## Method 2: Using EC2 Instance Connect or SSH

If you have SSH access configured:

```bash
# Get bastion public IP (if available)
cd terraform
BASTION_IP=$(terraform output -raw bastion_public_ip 2>/dev/null || echo "not-available")

# Copy script using SCP
scp -i /path/to/your-key.pem terraform/scripts/configure-aurora-binlog.sh ec2-user@$BASTION_IP:~/

# Connect and execute
ssh -i /path/to/your-key.pem ec2-user@$BASTION_IP
chmod +x ~/configure-aurora-binlog.sh
./configure-aurora-binlog.sh
```

---

## Method 3: Using AWS Systems Manager Send Command

Send the script directly without connecting:

```bash
# Get bastion instance ID
cd terraform
BASTION_ID=$(terraform output -raw bastion_instance_id)

# Read the script content
SCRIPT_CONTENT=$(cat scripts/configure-aurora-binlog.sh)

# Send command to execute
aws ssm send-command \
    --instance-ids "$BASTION_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[\"$SCRIPT_CONTENT\"]" \
    --region us-east-1 \
    --output text \
    --query 'Command.CommandId'

# Check command status (replace COMMAND_ID with the output from above)
aws ssm get-command-invocation \
    --command-id COMMAND_ID \
    --instance-id "$BASTION_ID" \
    --region us-east-1
```

---

## Method 4: Using User Data or AWS Systems Manager Parameter Store

### Store script in Parameter Store and retrieve on bastion:

```bash
# Store the script in Parameter Store (local terminal)
aws ssm put-parameter \
    --name "/msk-workshop/configure-aurora-script" \
    --type "String" \
    --value "$(cat terraform/scripts/configure-aurora-binlog.sh)" \
    --region us-east-1 \
    --overwrite

# In SSM session on bastion:
aws ssm get-parameter \
    --name "/msk-workshop/configure-aurora-script" \
    --query "Parameter.Value" \
    --output text \
    --region us-east-1 > ~/configure-aurora-binlog.sh

chmod +x ~/configure-aurora-binlog.sh
./configure-aurora-binlog.sh

# Clean up (optional)
aws ssm delete-parameter \
    --name "/msk-workshop/configure-aurora-script" \
    --region us-east-1
```

---

## Complete Step 2 Workflow (Recommended)

Here's the complete process for Step 2 of the Quick Start:

### 1. Connect to Bastion

```bash
cd terraform
BASTION_ID=$(terraform output -raw bastion_instance_id)
aws ssm start-session --target $BASTION_ID --region us-east-1
```

### 2. Install MySQL Client (if not already installed)

```bash
# In SSM session on bastion:
sudo yum install -y mysql
```

### 3. Run the Aurora Configuration Script

**Option A: Direct execution with script content**

```bash
# Copy the configure-aurora-binlog.sh script content and run it
# Use one of the methods above to get the script onto the bastion
./configure-aurora-binlog.sh
```

**Option B: Manual commands (if you prefer not to use the script)**

```bash
# Set variables
REGION="us-east-1"
CLUSTER_ID="aurora-cdc-cluster"
PARAM_GROUP_NAME="aurora-mysql-binlog"

# Create parameter group
aws rds create-db-cluster-parameter-group \
    --db-cluster-parameter-group-name "$PARAM_GROUP_NAME" \
    --db-parameter-group-family aurora-mysql8.0 \
    --description "Aurora MySQL with binary logging enabled for CDC" \
    --region "$REGION"

# Configure parameters
aws rds modify-db-cluster-parameter-group \
    --db-cluster-parameter-group-name "$PARAM_GROUP_NAME" \
    --parameters "ParameterName=binlog_format,ParameterValue=ROW,ApplyMethod=immediate" \
                 "ParameterName=binlog_row_image,ParameterValue=FULL,ApplyMethod=immediate" \
    --region "$REGION"

# Apply to cluster
aws rds modify-db-cluster \
    --db-cluster-identifier "$CLUSTER_ID" \
    --db-cluster-parameter-group-name "$PARAM_GROUP_NAME" \
    --apply-immediately \
    --region "$REGION"

# Get instance ID and reboot
INSTANCE_ID=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$CLUSTER_ID" \
    --query "DBClusters[0].DBClusterMembers[0].DBInstanceIdentifier" \
    --output text \
    --region "$REGION")

aws rds reboot-db-instance \
    --db-instance-identifier "$INSTANCE_ID" \
    --region "$REGION"

# Wait for instance to be available (check status)
aws rds describe-db-instances \
    --db-instance-identifier "$INSTANCE_ID" \
    --query "DBInstances[0].DBInstanceStatus" \
    --output text \
    --region "$REGION"
```

### 4. Configure Database and Create Tables

Once Aurora is available (after the reboot completes):

```bash
# Get Aurora endpoint
AURORA_ENDPOINT=$(aws rds describe-db-clusters \
    --db-cluster-identifier aurora-cdc-cluster \
    --query "DBClusters[0].Endpoint" \
    --output text \
    --region us-east-1)

echo "Aurora endpoint: $AURORA_ENDPOINT"

# Connect to MySQL (you'll be prompted for password)
mysql -h $AURORA_ENDPOINT -u admin -p
```

Then run the SQL commands:

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

---

## Troubleshooting

### SSM Session Won't Start

- Verify the bastion instance has the SSM agent running
- Check that the IAM role attached to the bastion has SSM permissions
- Ensure the instance is in a running state

```bash
aws ec2 describe-instances --instance-ids $BASTION_ID --region us-east-1
```

### Script Permission Denied

Make sure the script is executable:

```bash
chmod +x ~/configure-aurora-binlog.sh
ls -la ~/configure-aurora-binlog.sh
```

### AWS CLI Not Found on Bastion

The bastion should have AWS CLI pre-installed. If not:

```bash
# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### Cannot Connect to Aurora from Bastion

- Verify security groups allow traffic from bastion to Aurora
- Check that Aurora is in the same VPC
- Ensure Aurora endpoint is correct

```bash
# Test connectivity
telnet $AURORA_ENDPOINT 3306
```

---

## Quick Reference

**Get Bastion ID:**
```bash
terraform output -raw bastion_instance_id
```

**Get Aurora Endpoint:**
```bash
terraform output -raw aurora_endpoint
```

**Connect to Bastion:**
```bash
aws ssm start-session --target $(terraform output -raw bastion_instance_id) --region us-east-1
```

**Check Aurora Status:**
```bash
aws rds describe-db-instances \
    --db-instance-identifier $(terraform output -raw aurora_instance_id) \
    --query "DBInstances[0].DBInstanceStatus" \
    --output text
```
