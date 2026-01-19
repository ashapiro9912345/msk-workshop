#!/bin/bash
# Configure Aurora MySQL with binary logging for Debezium CDC
# This script creates a parameter group with binary logging enabled and applies it to the Aurora cluster.
# Binary logging is required for Debezium to capture database changes.

set -e

echo ""
echo "========================================"
echo "   Configure Aurora Binary Logging"
echo "========================================"
echo ""

REGION="us-east-1"
CLUSTER_ID="aurora-cdc-cluster"
PARAM_GROUP_NAME="aurora-mysql-binlog"
PARAM_GROUP_FAMILY="aurora-mysql8.0"

# Step 1: Create parameter group with binary logging
echo "[*] Creating Aurora parameter group with binary logging..."

if aws rds create-db-cluster-parameter-group \
    --db-cluster-parameter-group-name "$PARAM_GROUP_NAME" \
    --db-parameter-group-family "$PARAM_GROUP_FAMILY" \
    --description "Aurora MySQL with binary logging enabled for CDC" \
    --region "$REGION" > /dev/null 2>&1; then
    echo "[OK] Parameter group created"
else
    echo "[WARN] Parameter group may already exist"
fi

echo ""

# Step 2: Set binary logging parameters
echo "[*] Configuring binary logging parameters..."

aws rds modify-db-cluster-parameter-group \
    --db-cluster-parameter-group-name "$PARAM_GROUP_NAME" \
    --parameters "ParameterName=binlog_format,ParameterValue=ROW,ApplyMethod=immediate" \
                 "ParameterName=binlog_row_image,ParameterValue=FULL,ApplyMethod=immediate" \
    --region "$REGION" > /dev/null

echo "[OK] Binary logging parameters configured"
echo ""

# Step 3: Apply parameter group to Aurora cluster
echo "[*] Applying parameter group to Aurora cluster..."

aws rds modify-db-cluster \
    --db-cluster-identifier "$CLUSTER_ID" \
    --db-cluster-parameter-group-name "$PARAM_GROUP_NAME" \
    --apply-immediately \
    --region "$REGION" > /dev/null

echo "[OK] Parameter group applied to cluster"
echo ""

# Step 4: Get Aurora instance ID and reboot
echo "[*] Getting Aurora instance ID..."

INSTANCE_ID=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$CLUSTER_ID" \
    --query "DBClusters[0].DBClusterMembers[0].DBInstanceIdentifier" \
    --output text \
    --region "$REGION")

echo "[OK] Aurora instance ID: $INSTANCE_ID"
echo ""

echo "[*] Rebooting Aurora instance to apply changes..."

aws rds reboot-db-instance \
    --db-instance-identifier "$INSTANCE_ID" \
    --region "$REGION" > /dev/null

echo "[OK] Reboot initiated"
echo ""

echo "========================================"
echo "[*] Waiting for Aurora to become available (this may take 5-10 minutes)..."
echo ""

# Wait for Aurora to become available
MAX_ATTEMPTS=30
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    STATUS=$(aws rds describe-db-instances \
        --db-instance-identifier "$INSTANCE_ID" \
        --query "DBInstances[0].DBInstanceStatus" \
        --output text \
        --region "$REGION")

    echo "[*] Current status: $STATUS"

    if [ "$STATUS" = "available" ]; then
        echo ""
        echo "[OK] Aurora is now available!"
        echo ""
        echo "Binary logging is now enabled. You can proceed with connector deployment."
        echo ""
        exit 0
    fi

    ATTEMPT=$((ATTEMPT + 1))
    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
        sleep 20
    fi
done

echo ""
echo "[WARN] Aurora is still not available after waiting. Check status manually:"
echo "  aws rds describe-db-instances --db-instance-identifier $INSTANCE_ID --query 'DBInstances[0].DBInstanceStatus'"
echo ""
