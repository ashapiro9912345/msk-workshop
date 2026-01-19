<#
.SYNOPSIS
Deploy MSK Connect connectors from generated configuration files.

.DESCRIPTION
This script deploys Debezium and JDBC connectors to MSK Connect using
the AWS CLI. It automatically retrieves plugin ARNs, service role ARN,
and connector configurations from generated files.

.PARAMETER ConnectorType
Specify which connector to deploy: 'debezium', 'jdbc', or 'all' (default)

.PARAMETER MCUCount
Number of MSK Connect Units (MCU) per connector. Default: 1

.PARAMETER WorkerConfigArn
Optional: ARN of worker configuration. If not provided, uses default settings.

.EXAMPLE
.\deploy-connectors.ps1
Deploys all connectors with default settings

.EXAMPLE
.\deploy-connectors.ps1 -ConnectorType debezium -MCUCount 2
Deploys only Debezium connector with 2 MCUs

.NOTES
Requires: AWS CLI, generated connector configs, MSK Connect custom plugins
#>

param(
    [ValidateSet('all', 'debezium', 'jdbc')]
    [string]$ConnectorType = 'all',

    [int]$MCUCount = 1,

    [string]$RoleName = 'msk-connect-exec-role',

    [string]$Region = 'us-east-1',

    [string]$WorkerConfigArn = '',

    [string]$GeneratedDir = '..\connectors\generated'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== MSK Connect Connector Deployment ===" -ForegroundColor Cyan
Write-Host ""

# Resolve paths
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$terraformDir = Resolve-Path "$scriptDir\.."
$generatedDir = Join-Path $terraformDir "connectors\generated"

if (-not (Test-Path $generatedDir)) {
    Write-Error @"
Generated connector configs not found at: $generatedDir

Please run: .\generate-connector-configs.ps1 first
"@
    exit 1
}

# Check AWS CLI
try {
    $awsVersion = aws --version 2>&1
    Write-Host "[OK] AWS CLI: $awsVersion" -ForegroundColor Green
} catch {
    Write-Error "AWS CLI not found. Please install AWS CLI v2."
    exit 1
}

# Verify AWS credentials
Write-Host "Verifying AWS credentials..." -ForegroundColor Yellow
try {
    $identity = aws sts get-caller-identity --query 'Account' --output text 2>&1
    Write-Host "[OK] AWS Account: $identity" -ForegroundColor Green
} catch {
    Write-Error "Failed to verify AWS credentials. Run 'aws configure' first."
    exit 1
}
Write-Host ""

# Get IAM role ARN
Write-Host "Getting MSK Connect service role..." -ForegroundColor Yellow
try {
    $roleArn = aws iam get-role --role-name $RoleName --query 'Role.Arn' --output text 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Role not found"
    }
    Write-Host "[OK] Service Role: $roleArn" -ForegroundColor Green
} catch {
    Write-Error @"
Failed to get IAM role '$RoleName'.

Ensure Terraform has created the role:
  cd terraform
  terraform apply
"@
    exit 1
}

# Get custom plugin ARNs
Write-Host "Getting MSK Connect custom plugins..." -ForegroundColor Yellow
try {
    $pluginsJson = aws kafkaconnect list-custom-plugins --region $Region 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to list plugins"
    }
    $plugins = $pluginsJson | ConvertFrom-Json

    $debeziumPlugin = $plugins.customPlugins | Where-Object { $_.name -like "*debezium*" } | Select-Object -First 1
    $jdbcPlugin = $plugins.customPlugins | Where-Object { $_.name -like "*jdbc*" } | Select-Object -First 1

    if ($debeziumPlugin) {
        Write-Host "[OK] Debezium Plugin: $($debeziumPlugin.name) (revision $($debeziumPlugin.latestRevision.revision))" -ForegroundColor Green
    } else {
        Write-Warning "Debezium plugin not found. Ensure Terraform created it with create_connectors=true"
    }

    if ($jdbcPlugin) {
        Write-Host "[OK] JDBC Plugin: $($jdbcPlugin.name) (revision $($jdbcPlugin.latestRevision.revision))" -ForegroundColor Green
    } else {
        Write-Warning "JDBC plugin not found. Ensure Terraform created it with create_connectors=true"
    }
} catch {
    Write-Error "Failed to retrieve custom plugins: $_"
    exit 1
}
Write-Host ""

# Get MSK bootstrap brokers from Terraform
Write-Host "Getting MSK cluster information..." -ForegroundColor Yellow
Push-Location $terraformDir
try {
    $bootstrapBrokers = terraform output -raw msk_bootstrap_brokers 2>$null
    if (-not $bootstrapBrokers) {
        throw "Bootstrap brokers output is empty"
    }
    Write-Host "[OK] Bootstrap Brokers: $bootstrapBrokers" -ForegroundColor Green
} catch {
    Write-Error "Failed to get MSK bootstrap brokers from Terraform outputs"
    Pop-Location
    exit 1
} finally {
    Pop-Location
}
Write-Host ""

# Function to deploy a connector
function Deploy-Connector {
    param(
        [string]$ConfigFile,
        [hashtable]$Plugins,
        [string]$LogGroupPrefix
    )

    $configPath = Join-Path $generatedDir $ConfigFile
    if (-not (Test-Path $configPath)) {
        Write-Warning "Config file not found: $configPath - Skipping"
        return $false
    }

    Write-Host "Reading configuration: $ConfigFile" -ForegroundColor Yellow
    $configContent = Get-Content $configPath -Raw | ConvertFrom-Json

    $connectorName = $configContent.name
    $connectorConfig = $configContent.config

    # Check if connector already exists
    Write-Host "Checking if connector '$connectorName' already exists..." -ForegroundColor Yellow
    $existingConnectors = aws kafkaconnect list-connectors --region $Region --query "connectors[?connectorName=='$connectorName'].connectorName" --output text 2>&1
    if ($existingConnectors -eq $connectorName) {
        Write-Warning "Connector '$connectorName' already exists. Skipping creation."
        Write-Host "To redeploy, first delete the existing connector:"
        Write-Host "  aws kafkaconnect delete-connector --connector-arn <ARN> --region $Region"
        return $false
    }

    # Build Kafka cluster configuration
    $kafkaCluster = @{
        apacheKafkaCluster = @{
            bootstrapServers = $bootstrapBrokers
            vpc = @{
                securityGroups = @()
                subnets = @()
            }
        }
    }

    # Get VPC configuration from Terraform
    Push-Location $terraformDir
    try {
        # Get security group IDs
        $mskSgId = terraform output -json 2>$null | ConvertFrom-Json | Select-Object -ExpandProperty msk_sg_id -ErrorAction SilentlyContinue
        if (-not $mskSgId) {
            # Fallback: query AWS for the security group
            $mskSgId = aws ec2 describe-security-groups --region $Region --filters "Name=group-name,Values=msk-sg" --query "SecurityGroups[0].GroupId" --output text 2>&1
        }

        # Get private subnet IDs
        $vpcId = terraform output -raw vpc_id 2>$null
        $subnetIds = aws ec2 describe-subnets --region $Region --filters "Name=vpc-id,Values=$vpcId" "Name=tag:Name,Values=private-*" --query "Subnets[*].SubnetId" --output json 2>&1 | ConvertFrom-Json

        if ($mskSgId) {
            $kafkaCluster.apacheKafkaCluster.vpc.securityGroups = @($mskSgId)
        }
        if ($subnetIds) {
            $kafkaCluster.apacheKafkaCluster.vpc.subnets = $subnetIds
        }
    } finally {
        Pop-Location
    }

    # Build plugins array
    $pluginsArray = @()
    foreach ($pluginName in $Plugins.Keys) {
        $plugin = $Plugins[$pluginName]
        if ($plugin) {
            $pluginsArray += @{
                customPlugin = @{
                    customPluginArn = $plugin.customPluginArn
                    revision = $plugin.latestRevision.revision
                }
            }
        }
    }

    # Build capacity configuration
    $capacity = @{
        provisionedCapacity = @{
            mcuCount = $MCUCount
            workerCount = 1
        }
    }

    # Build log delivery configuration
    $logGroupName = "/aws/mskconnect/$connectorName"
    $logDelivery = @{
        workerLogDelivery = @{
            cloudWatchLogs = @{
                enabled = $true
                logGroup = $logGroupName
            }
        }
    }

    # Create CloudWatch log group
    Write-Host "Creating CloudWatch log group: $logGroupName" -ForegroundColor Yellow
    aws logs create-log-group --log-group-name $logGroupName --region $Region 2>$null
    # Ignore error if already exists

    # Convert to JSON
    $kafkaClusterJson = $kafkaCluster | ConvertTo-Json -Depth 10 -Compress
    $configJson = $connectorConfig | ConvertTo-Json -Depth 10 -Compress
    $capacityJson = $capacity | ConvertTo-Json -Depth 10 -Compress
    $pluginsJson = $pluginsArray | ConvertTo-Json -Depth 10 -Compress
    $logDeliveryJson = $logDelivery | ConvertTo-Json -Depth 10 -Compress

    # Build AWS CLI command
    Write-Host "Creating connector: $connectorName" -ForegroundColor Cyan
    Write-Host "  MCU Count: $MCUCount" -ForegroundColor Gray
    Write-Host "  Plugins: $($pluginsArray.Count)" -ForegroundColor Gray
    Write-Host ""

    $command = @(
        'aws', 'kafkaconnect', 'create-connector',
        '--connector-name', $connectorName,
        '--kafka-cluster', $kafkaClusterJson,
        '--capacity', $capacityJson,
        '--connector-configuration', $configJson,
        '--plugins', $pluginsJson,
        '--service-execution-role-arn', $roleArn,
        '--log-delivery', $logDeliveryJson,
        '--region', $Region
    )

    if ($WorkerConfigArn) {
        $command += @('--worker-configuration', "arn=$WorkerConfigArn")
    }

    # Execute command
    try {
        $result = & $command[0] $command[1..($command.Length-1)] 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create connector: $result"
            return $false
        }

        $resultObj = $result | ConvertFrom-Json
        Write-Host "[OK] Connector created successfully!" -ForegroundColor Green
        Write-Host "  Connector ARN: $($resultObj.connectorArn)" -ForegroundColor Green
        Write-Host "  State: $($resultObj.connectorState)" -ForegroundColor Green
        Write-Host ""
        Write-Host "Monitor status with:" -ForegroundColor Yellow
        Write-Host "  aws kafkaconnect describe-connector --connector-arn $($resultObj.connectorArn) --region $Region" -ForegroundColor Gray
        Write-Host ""

        return $true
    } catch {
        Write-Error "Exception during connector creation: $_"
        return $false
    }
}

# Deploy connectors based on selection
$deploymentResults = @{}

if ($ConnectorType -eq 'all' -or $ConnectorType -eq 'debezium') {
    if ($debeziumPlugin) {
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Deploying Debezium Source Connector" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""

        $plugins = @{ 'debezium' = $debeziumPlugin }
        $deploymentResults['debezium'] = Deploy-Connector `
            -ConfigFile 'debezium-aurora-mysql-source.json' `
            -Plugins $plugins `
            -LogGroupPrefix 'debezium'
    } else {
        Write-Warning "Skipping Debezium connector (plugin not found)"
    }
}

if ($ConnectorType -eq 'all' -or $ConnectorType -eq 'jdbc') {
    if ($jdbcPlugin) {
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Deploying JDBC Sink Connector" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""

        $plugins = @{ 'jdbc' = $jdbcPlugin }
        $deploymentResults['jdbc'] = Deploy-Connector `
            -ConfigFile 'redshift-jdbc-sink.json' `
            -Plugins $plugins `
            -LogGroupPrefix 'jdbc'
    } else {
        Write-Warning "Skipping JDBC connector (plugin not found or Redshift not deployed)"
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deployment Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

foreach ($connector in $deploymentResults.Keys) {
    $status = if ($deploymentResults[$connector]) { "[OK] SUCCESS" } else { "[FAIL] FAILED/SKIPPED" }
    $color = if ($deploymentResults[$connector]) { "Green" } else { "Red" }
    Write-Host "${connector}: $status" -ForegroundColor $color
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Wait 5-10 minutes for connectors to reach RUNNING state"
Write-Host "  2. Check connector status:"
Write-Host "     aws kafkaconnect list-connectors --region $Region"
Write-Host "  3. View logs in CloudWatch Logs console"
Write-Host "  4. Insert test data into Aurora to verify CDC"
Write-Host ""
