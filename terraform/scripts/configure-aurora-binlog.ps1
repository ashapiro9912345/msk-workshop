#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Configure Aurora MySQL with binary logging for Debezium CDC
.DESCRIPTION
    This script creates a parameter group with binary logging enabled and applies it to the Aurora cluster.
    Binary logging is required for Debezium to capture database changes.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   Configure Aurora Binary Logging" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$terraformDir = Split-Path -Parent $scriptDir
Set-Location $terraformDir

# Step 1: Create parameter group with binary logging
Write-Host "[*] Creating Aurora parameter group with binary logging..." -ForegroundColor Yellow

try {
    aws rds create-db-cluster-parameter-group `
        --db-cluster-parameter-group-name aurora-mysql-binlog `
        --db-parameter-group-family aurora-mysql8.0 `
        --description "Aurora MySQL with binary logging enabled for CDC" `
        --region us-east-1 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Parameter group created" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Parameter group may already exist" -ForegroundColor Yellow
    }
} catch {
    Write-Host "[WARN] Parameter group may already exist: $_" -ForegroundColor Yellow
}

Write-Host ""

# Step 2: Set binary logging parameters
Write-Host "[*] Configuring binary logging parameters..." -ForegroundColor Yellow

aws rds modify-db-cluster-parameter-group `
    --db-cluster-parameter-group-name aurora-mysql-binlog `
    --parameters "ParameterName=binlog_format,ParameterValue=ROW,ApplyMethod=immediate" `
                 "ParameterName=binlog_row_image,ParameterValue=FULL,ApplyMethod=immediate" `
    --region us-east-1 | Out-Null

Write-Host "[OK] Binary logging parameters configured" -ForegroundColor Green
Write-Host ""

# Step 3: Apply parameter group to Aurora cluster
Write-Host "[*] Applying parameter group to Aurora cluster..." -ForegroundColor Yellow

aws rds modify-db-cluster `
    --db-cluster-identifier aurora-cdc-cluster `
    --db-cluster-parameter-group-name aurora-mysql-binlog `
    --apply-immediately `
    --region us-east-1 | Out-Null

Write-Host "[OK] Parameter group applied to cluster" -ForegroundColor Green
Write-Host ""

# Step 4: Get Aurora instance ID and reboot
Write-Host "[*] Getting Aurora instance ID..." -ForegroundColor Yellow

$instanceId = aws rds describe-db-clusters `
    --db-cluster-identifier aurora-cdc-cluster `
    --query "DBClusters[0].DBClusterMembers[0].DBInstanceIdentifier" `
    --output text `
    --region us-east-1

Write-Host "[OK] Aurora instance ID: $instanceId" -ForegroundColor Green
Write-Host ""

Write-Host "[*] Rebooting Aurora instance to apply changes..." -ForegroundColor Yellow

aws rds reboot-db-instance `
    --db-instance-identifier $instanceId `
    --region us-east-1 | Out-Null

Write-Host "[OK] Reboot initiated" -ForegroundColor Green
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[*] Waiting for Aurora to become available (this may take 5-10 minutes)..." -ForegroundColor Yellow
Write-Host ""

# Wait for Aurora to become available
$maxAttempts = 30
$attempt = 0

while ($attempt -lt $maxAttempts) {
    $status = aws rds describe-db-instances `
        --db-instance-identifier $instanceId `
        --query "DBInstances[0].DBInstanceStatus" `
        --output text `
        --region us-east-1

    Write-Host "[*] Current status: $status" -ForegroundColor Cyan

    if ($status -eq "available") {
        Write-Host ""
        Write-Host "[OK] Aurora is now available!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Binary logging is now enabled. You can proceed with connector deployment." -ForegroundColor Green
        Write-Host ""
        exit 0
    }

    $attempt++
    if ($attempt -lt $maxAttempts) {
        Start-Sleep -Seconds 20
    }
}

Write-Host ""
Write-Host "[WARN] Aurora is still not available after waiting. Check status manually:" -ForegroundColor Yellow
Write-Host "  aws rds describe-db-instances --db-instance-identifier $instanceId --query 'DBInstances[0].DBInstanceStatus'" -ForegroundColor Gray
Write-Host ""
