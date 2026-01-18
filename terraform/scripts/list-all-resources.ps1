#!/usr/bin/env pwsh
<#
.SYNOPSIS
    List all AWS resources for the MSK CDC workshop
.DESCRIPTION
    This script lists all AWS resources created by Terraform and manual deployment,
    showing their current state and estimated costs.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$Region = "us-east-1"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   AWS Resources Inventory" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# VPC Resources
Write-Host "=== VPC Resources ===" -ForegroundColor Yellow
try {
    $vpcs = aws ec2 describe-vpcs --region $Region --filters "Name=tag:Name,Values=msk-cdc-vpc" --query "Vpcs[*].[Tags[?Key=='Name'].Value | [0],VpcId,CidrBlock,State]" --output table 2>$null
    if ($vpcs) { Write-Host $vpcs } else { Write-Host "No VPCs found" -ForegroundColor Gray }
} catch { Write-Host "Error listing VPCs" -ForegroundColor Red }
Write-Host ""

# EC2 Instances (Bastion)
Write-Host "=== EC2 Instances ===" -ForegroundColor Yellow
try {
    $instances = aws ec2 describe-instances --region $Region --filters "Name=tag:Name,Values=msk-workshop-bastion" "Name=instance-state-name,Values=pending,running,stopping,stopped" --query "Reservations[*].Instances[*].[Tags[?Key=='Name'].Value | [0],InstanceId,InstanceType,State.Name,PublicIpAddress]" --output table 2>$null
    if ($instances) { Write-Host $instances } else { Write-Host "No EC2 instances found" -ForegroundColor Gray }
} catch { Write-Host "Error listing EC2 instances" -ForegroundColor Red }
Write-Host ""

# MSK Clusters
Write-Host "=== MSK Clusters ===" -ForegroundColor Yellow
try {
    $mskClusters = aws kafka list-clusters --region $Region --query "ClusterInfoList[*].[ClusterName,State,NumberOfBrokerNodes]" --output table 2>$null
    if ($mskClusters) {
        Write-Host $mskClusters
        # Get broker details
        $clusterArn = aws kafka list-clusters --region $Region --query "ClusterInfoList[0].ClusterArn" --output text 2>$null
        if ($clusterArn -and $clusterArn -ne "None") {
            Write-Host "`nBroker Node Type:" -ForegroundColor Cyan
            aws kafka describe-cluster --cluster-arn $clusterArn --query "ClusterInfo.BrokerNodeGroupInfo.InstanceType" --output text 2>$null
        }
    } else {
        Write-Host "No MSK clusters found" -ForegroundColor Gray
    }
} catch { Write-Host "Error listing MSK clusters" -ForegroundColor Red }
Write-Host ""

# MSK Connect Connectors
Write-Host "=== MSK Connect Connectors ===" -ForegroundColor Yellow
try {
    $connectors = aws kafkaconnect list-connectors --region $Region --query "connectors[*].[connectorName,connectorState,connectorArn]" --output table 2>$null
    if ($connectors) { Write-Host $connectors } else { Write-Host "No connectors found" -ForegroundColor Gray }
} catch { Write-Host "Error listing connectors" -ForegroundColor Red }
Write-Host ""

# MSK Connect Custom Plugins
Write-Host "=== MSK Connect Custom Plugins ===" -ForegroundColor Yellow
try {
    $plugins = aws kafkaconnect list-custom-plugins --region $Region --query "customPlugins[*].[name,customPluginState]" --output table 2>$null
    if ($plugins) { Write-Host $plugins } else { Write-Host "No custom plugins found" -ForegroundColor Gray }
} catch { Write-Host "Error listing custom plugins" -ForegroundColor Red }
Write-Host ""

# RDS/Aurora Clusters
Write-Host "=== Aurora DB Clusters ===" -ForegroundColor Yellow
try {
    $dbClusters = aws rds describe-db-clusters --region $Region --query "DBClusters[*].[DBClusterIdentifier,Status,Engine,EngineVersion,DBClusterParameterGroup]" --output table 2>$null
    if ($dbClusters) {
        Write-Host $dbClusters
        # Get instance details
        Write-Host "`nAurora Instances:" -ForegroundColor Cyan
        $dbInstances = aws rds describe-db-instances --region $Region --query "DBInstances[?DBClusterIdentifier!=null].[DBInstanceIdentifier,DBInstanceClass,DBInstanceStatus]" --output table 2>$null
        if ($dbInstances) { Write-Host $dbInstances }
    } else {
        Write-Host "No Aurora clusters found" -ForegroundColor Gray
    }
} catch { Write-Host "Error listing Aurora clusters" -ForegroundColor Red }
Write-Host ""

# RDS Parameter Groups
Write-Host "=== RDS Parameter Groups ===" -ForegroundColor Yellow
try {
    $paramGroups = aws rds describe-db-cluster-parameter-groups --region $Region --query "DBClusterParameterGroups[?DBClusterParameterGroupName=='aurora-mysql-binlog'].[DBClusterParameterGroupName,DBParameterGroupFamily,Description]" --output table 2>$null
    if ($paramGroups) { Write-Host $paramGroups } else { Write-Host "No custom parameter groups found" -ForegroundColor Gray }
} catch { Write-Host "Error listing parameter groups" -ForegroundColor Red }
Write-Host ""

# S3 Buckets
Write-Host "=== S3 Buckets ===" -ForegroundColor Yellow
try {
    $allBuckets = aws s3api list-buckets --query "Buckets[*].[Name,CreationDate]" --output json 2>$null | ConvertFrom-Json
    $mskBuckets = $allBuckets | Where-Object { $_[0] -like "*msk-connector-plugins*" }
    if ($mskBuckets) {
        Write-Host "Bucket Name                                           Creation Date"
        Write-Host "----------------------------------------------------  -------------------------"
        foreach ($bucket in $mskBuckets) {
            Write-Host ("{0,-52}  {1}" -f $bucket[0], $bucket[1])
        }
    } else {
        Write-Host "No MSK connector plugin buckets found" -ForegroundColor Gray
    }
} catch { Write-Host "Error listing S3 buckets" -ForegroundColor Red }
Write-Host ""

# IAM Roles
Write-Host "=== IAM Roles ===" -ForegroundColor Yellow
try {
    $roles = aws iam list-roles --query "Roles[?contains(RoleName, 'msk-connect') || contains(RoleName, 'bastion')].[RoleName,CreateDate]" --output table 2>$null
    if ($roles) { Write-Host $roles } else { Write-Host "No MSK/bastion IAM roles found" -ForegroundColor Gray }
} catch { Write-Host "Error listing IAM roles" -ForegroundColor Red }
Write-Host ""

# CloudWatch Log Groups
Write-Host "=== CloudWatch Log Groups ===" -ForegroundColor Yellow
try {
    $logGroups = aws logs describe-log-groups --region $Region --log-group-name-prefix "msk" --query "logGroups[*].[logGroupName,storedBytes]" --output table 2>$null
    if ($logGroups) { Write-Host $logGroups } else { Write-Host "No MSK log groups found" -ForegroundColor Gray }
} catch { Write-Host "Error listing log groups" -ForegroundColor Red }
Write-Host ""

# Security Groups
Write-Host "=== Security Groups ===" -ForegroundColor Yellow
try {
    $securityGroups = aws ec2 describe-security-groups --region $Region --query "SecurityGroups[?contains(GroupName, 'bastion') || contains(GroupName, 'msk')].[GroupName,GroupId,VpcId,Description]" --output table 2>$null
    if ($securityGroups) { Write-Host $securityGroups } else { Write-Host "No bastion/MSK security groups found" -ForegroundColor Gray }
} catch { Write-Host "Error listing security groups" -ForegroundColor Red }
Write-Host ""

# Estimated Costs
Write-Host "=== Estimated Hourly Costs ===" -ForegroundColor Yellow
Write-Host ""

$totalCost = 0

# MSK - only show if cluster exists
try {
    $mskClusterExists = aws kafka list-clusters --region $Region --query "length(ClusterInfoList)" --output text 2>$null
    if ($mskClusterExists -and $mskClusterExists -ne "0") {
        $clusterArn = aws kafka list-clusters --region $Region --query "ClusterInfoList[0].ClusterArn" --output text 2>$null
        $mskBrokers = aws kafka list-clusters --region $Region --query "ClusterInfoList[0].NumberOfBrokerNodes" --output text 2>$null
        $mskInstanceType = aws kafka describe-cluster --cluster-arn $clusterArn --query "ClusterInfo.BrokerNodeGroupInfo.InstanceType" --output text 2>$null
        $mskCostPerBroker = 0.21
        $mskCost = [int]$mskBrokers * $mskCostPerBroker
        Write-Host "MSK ($mskBrokers x $mskInstanceType): `$$mskCost/hour" -ForegroundColor White
        $totalCost += $mskCost
    }
} catch { }

# Aurora
try {
    $auroraInstance = aws rds describe-db-instances --region $Region --query "DBInstances[?DBClusterIdentifier!=null].DBInstanceClass | [0]" --output text 2>$null
    if ($auroraInstance -and $auroraInstance -ne "None") {
        $auroraCost = if ($auroraInstance -match "db.r5.large") { 0.29 } else { 0.15 }
        Write-Host "Aurora ($auroraInstance): `$$auroraCost/hour" -ForegroundColor White
        $totalCost += $auroraCost
    }
} catch { }

# Bastion
try {
    $bastionInstance = aws ec2 describe-instances --region $Region --filters "Name=tag:Name,Values=msk-workshop-bastion" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].InstanceType | [0][0]" --output text 2>$null
    if ($bastionInstance -and $bastionInstance -ne "None") {
        $bastionCost = if ($bastionInstance -match "t3.micro") { 0.0104 } else { 0.02 }
        Write-Host "Bastion ($bastionInstance): `$$bastionCost/hour" -ForegroundColor White
        $totalCost += $bastionCost
    }
} catch { }

# MSK Connect
$connectorCount = 0
try {
    $connectorCountStr = aws kafkaconnect list-connectors --region $Region --query "length(connectors[?connectorState=='RUNNING'])" --output text 2>$null
    if ($connectorCountStr -and $connectorCountStr -ne "0") {
        $connectorCount = [int]$connectorCountStr
        $connectorCost = $connectorCount * 0.11
        Write-Host "MSK Connect ($connectorCount connectors): `$$connectorCost/hour" -ForegroundColor White
        $totalCost += $connectorCost
    }
} catch { }

Write-Host ""
Write-Host "Total Estimated Cost: `$$totalCost/hour (~`$$([math]::Round($totalCost * 24, 2))/day)" -ForegroundColor Cyan
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "To destroy all resources, run: terraform destroy" -ForegroundColor Yellow
Write-Host ""
