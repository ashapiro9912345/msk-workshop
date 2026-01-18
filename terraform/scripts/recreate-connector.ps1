#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Recreate the Debezium connector after Aurora binary logging configuration
.DESCRIPTION
    This script recreates the Debezium source connector using the file:// protocol
    method that worked for complex JSON parameters.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   Recreate Debezium Source Connector" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$terraformDir = Split-Path -Parent $scriptDir
Set-Location $terraformDir

# Verify binary logging is enabled
Write-Host "[*] Verifying Aurora binary logging configuration..." -ForegroundColor Yellow
$paramGroup = aws rds describe-db-clusters `
    --db-cluster-identifier aurora-cdc-cluster `
    --query "DBClusters[0].DBClusterParameterGroup" `
    --output text

Write-Host "[OK] Current parameter group: $paramGroup" -ForegroundColor Green

if ($paramGroup -ne "aurora-mysql-binlog") {
    Write-Host "[WARN] Parameter group is not 'aurora-mysql-binlog'. Binary logging may not be configured correctly." -ForegroundColor Yellow
    $continue = Read-Host "Continue anyway? (yes/no)"
    if ($continue -ne "yes") {
        Write-Host "[*] Aborted by user" -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""

# Check if connector config files exist
$connectorConfigPath = ".\connector-config.json"
$kafkaClusterPath = ".\kafka-cluster.json"

if (-not (Test-Path $connectorConfigPath)) {
    Write-Host "[FAIL] Connector config not found at: $connectorConfigPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $kafkaClusterPath)) {
    Write-Host "[FAIL] Kafka cluster config not found at: $kafkaClusterPath" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Configuration files found" -ForegroundColor Green
Write-Host ""

# Get plugin ARN
Write-Host "[*] Getting Debezium plugin ARN..." -ForegroundColor Yellow
$pluginArn = aws kafkaconnect list-custom-plugins `
    --query "customPlugins[?name=='debezium-plugin'].customPluginArn | [0]" `
    --output text

if (-not $pluginArn -or $pluginArn -eq "None") {
    Write-Host "[FAIL] Could not find Debezium plugin" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Plugin ARN: $pluginArn" -ForegroundColor Green
Write-Host ""

# Get worker configuration ARN
Write-Host "[*] Getting worker configuration ARN..." -ForegroundColor Yellow
$workerConfigArn = aws kafkaconnect list-worker-configurations `
    --query "workerConfigurations[?name=='msk-connect-worker-config'].workerConfigurationArn | [0]" `
    --output text

if (-not $workerConfigArn -or $workerConfigArn -eq "None") {
    Write-Host "[WARN] No worker configuration found, will use defaults" -ForegroundColor Yellow
    $workerConfigParam = ""
} else {
    Write-Host "[OK] Worker Config ARN: $workerConfigArn" -ForegroundColor Green
    $workerConfigParam = "--worker-configuration `"arn=$workerConfigArn,revision=1`""
}

Write-Host ""

# Get service execution role ARN
Write-Host "[*] Getting MSK Connect service role ARN..." -ForegroundColor Yellow
$roleArn = aws iam list-roles `
    --query "Roles[?RoleName=='msk-connect-exec-role'].Arn | [0]" `
    --output text

if (-not $roleArn -or $roleArn -eq "None") {
    Write-Host "[FAIL] Could not find msk-connect-exec-role" -ForegroundColor Red
    Write-Host "[*] You may need to create this role first" -ForegroundColor Yellow
    exit 1
}

Write-Host "[OK] Service Role ARN: $roleArn" -ForegroundColor Green
Write-Host ""

# Create the connector
Write-Host "[*] Creating Debezium source connector..." -ForegroundColor Yellow
Write-Host ""

# Create capacity.json
$capacityJson = @"
{
  "provisionedCapacity": {
    "mcuCount": 1,
    "workerCount": 1
  }
}
"@
[System.IO.File]::WriteAllText("$terraformDir\capacity.json", $capacityJson, [System.Text.Encoding]::ASCII)

# Create log-delivery.json
$logDeliveryJson = @"
{
  "workerLogDelivery": {
    "cloudWatchLogs": {
      "enabled": true,
      "logGroup": "msk-connect-logs"
    }
  }
}
"@
[System.IO.File]::WriteAllText("$terraformDir\log-delivery.json", $logDeliveryJson, [System.Text.Encoding]::ASCII)

# Create plugins.json
$pluginsJson = @"
[
  {
    "customPlugin": {
      "customPluginArn": "$pluginArn",
      "revision": 1
    }
  }
]
"@
[System.IO.File]::WriteAllText("$terraformDir\plugins.json", $pluginsJson, [System.Text.Encoding]::ASCII)

try {
    $connectorArn = aws kafkaconnect create-connector `
        --connector-name "debezium-source" `
        --kafka-cluster "file://$kafkaClusterPath" `
        --connector-configuration "file://$connectorConfigPath" `
        --capacity "file://capacity.json" `
        --plugins "file://plugins.json" `
        --service-execution-role-arn "$roleArn" `
        --log-delivery "file://log-delivery.json" `
        --kafka-cluster-client-authentication "authenticationType=NONE" `
        --kafka-cluster-encryption-in-transit "encryptionType=TLS" `
        --kafka-connect-version "2.7.1" `
        --query "connectorArn" `
        --output text

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "[FAIL] Failed to create connector" -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "[OK] Connector created successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Connector ARN: $connectorArn" -ForegroundColor White
    Write-Host ""
    Write-Host "[*] Checking connector status..." -ForegroundColor Yellow

    # Wait a few seconds for initial status
    Start-Sleep -Seconds 5

    $status = aws kafkaconnect describe-connector `
        --connector-arn "$connectorArn" `
        --query "connectorState" `
        --output text

    Write-Host "[*] Current status: $status" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Monitor the connector with:" -ForegroundColor Yellow
    Write-Host "  aws kafkaconnect describe-connector --connector-arn `"$connectorArn`"" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Check CloudWatch logs at:" -ForegroundColor Yellow
    Write-Host "  https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups/log-group/msk-connect-logs" -ForegroundColor Gray
    Write-Host ""

} catch {
    Write-Host ""
    Write-Host "[FAIL] Error creating connector: $_" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Connector recreation complete!" -ForegroundColor Green
Write-Host ""
