<#
.SYNOPSIS
Quick-start deployment script for the entire MSK Workshop stack.

.DESCRIPTION
This script automates the deployment of:
1. Infrastructure (VPC, MSK, Aurora, IAM roles)
2. Connector configuration generation
3. MSK Connect connector deployment

.PARAMETER SkipInfrastructure
Skip Terraform infrastructure deployment (use if already deployed)

.PARAMETER SkipConnectors
Skip connector deployment (only deploy infrastructure)

.EXAMPLE
.\quick-start.ps1
Full deployment from scratch

.EXAMPLE
.\quick-start.ps1 -SkipInfrastructure
Only deploy connectors (infrastructure already exists)

.NOTES
This is a convenience script for testing. For production, run steps individually.
#>

param(
    [switch]$SkipInfrastructure,
    [switch]$SkipConnectors
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$terraformDir = Resolve-Path "$scriptDir\.."

Write-Host @"
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║           MSK Workshop Quick-Start Deployment              ║
║                                                            ║
║  This will deploy the complete CDC pipeline:              ║
║  Aurora MySQL → Debezium → MSK → JDBC → Redshift          ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Host ""

# Pre-flight checks
Write-Host "=== Pre-flight Checks ===" -ForegroundColor Yellow
Write-Host ""

# Check Terraform
try {
    $tfVersion = terraform version -json | ConvertFrom-Json
    Write-Host "✓ Terraform: $($tfVersion.terraform_version)" -ForegroundColor Green
} catch {
    Write-Error "Terraform not found. Install from: https://www.terraform.io/downloads"
    exit 1
}

# Check AWS CLI
try {
    $awsVersion = aws --version 2>&1
    Write-Host "✓ AWS CLI: $awsVersion" -ForegroundColor Green
} catch {
    Write-Error "AWS CLI not found. Install from: https://aws.amazon.com/cli/"
    exit 1
}

# Check AWS credentials
try {
    $stsParams = @{
        'output' = 'json'
    }
    $identity = aws sts get-caller-identity @stsParams 2>&1 | ConvertFrom-Json
    Write-Host "✓ AWS Account: $($identity.Account)" -ForegroundColor Green
    Write-Host "✓ AWS Identity: $($identity.Arn)" -ForegroundColor Green
} catch {
    Write-Error "AWS credentials not configured. Run: aws configure"
    exit 1
}

# Check required files
$requiredFiles = @(
    (Join-Path $terraformDir "terraform.tfvars"),
    (Join-Path $terraformDir "secrets.auto.tfvars")
)

foreach ($file in $requiredFiles) {
    if (Test-Path $file) {
        Write-Host "✓ Found: $(Split-Path -Leaf $file)" -ForegroundColor Green
    } else {
        Write-Error "Missing required file: $file"
        exit 1
    }
}

Write-Host ""

# Phase 1: Infrastructure Deployment
if (-not $SkipInfrastructure) {
    Write-Host "=== Phase 1: Infrastructure Deployment ===" -ForegroundColor Cyan
    Write-Host ""

    Push-Location $terraformDir
    try {
        # Initialize Terraform
        Write-Host "Initializing Terraform..." -ForegroundColor Yellow
        terraform init
        if ($LASTEXITCODE -ne 0) {
            throw "Terraform init failed"
        }
        Write-Host "✓ Terraform initialized" -ForegroundColor Green
        Write-Host ""

        # Plan
        Write-Host "Creating deployment plan..." -ForegroundColor Yellow
        terraform plan -out=plan.tfplan
        if ($LASTEXITCODE -ne 0) {
            throw "Terraform plan failed"
        }
        Write-Host "✓ Plan created" -ForegroundColor Green
        Write-Host ""

        # Confirm
        Write-Host "Ready to deploy infrastructure. This will:" -ForegroundColor Yellow
        Write-Host "  • Create VPC, subnets, security groups" -ForegroundColor White
        Write-Host "  • Create MSK cluster (2 brokers) - ~15 minutes" -ForegroundColor White
        Write-Host "  • Create Aurora MySQL cluster - ~10 minutes" -ForegroundColor White
        Write-Host "  • Create IAM roles for MSK Connect" -ForegroundColor White
        Write-Host ""
        Write-Host "Estimated cost: ~$400/month (without Redshift)" -ForegroundColor Yellow
        Write-Host ""

        $confirm = Read-Host "Continue with deployment? (yes/no)"
        if ($confirm -ne 'yes') {
            Write-Host "Deployment cancelled" -ForegroundColor Red
            Pop-Location
            exit 0
        }

        # Apply
        Write-Host ""
        Write-Host "Deploying infrastructure (this will take 15-25 minutes)..." -ForegroundColor Cyan
        Write-Host ""
        terraform apply plan.tfplan
        if ($LASTEXITCODE -ne 0) {
            throw "Terraform apply failed"
        }

        Write-Host ""
        Write-Host "✓ Infrastructure deployed successfully!" -ForegroundColor Green
        Write-Host ""

        # Show outputs
        Write-Host "=== Infrastructure Details ===" -ForegroundColor Cyan
        terraform output
        Write-Host ""

    } catch {
        Write-Error "Infrastructure deployment failed: $_"
        Pop-Location
        exit 1
    } finally {
        Pop-Location
    }
} else {
    Write-Host "=== Phase 1: Infrastructure Deployment [SKIPPED] ===" -ForegroundColor Yellow
    Write-Host ""
}

# Phase 2: Aurora Configuration
Write-Host "=== Phase 2: Aurora Configuration ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "IMPORTANT: Before proceeding with connectors, you must:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Enable binary logging on Aurora:" -ForegroundColor White
Write-Host "   - Create DB Cluster Parameter Group with:" -ForegroundColor Gray
Write-Host "     • binlog_format = ROW" -ForegroundColor Gray
Write-Host "     • binlog_row_image = FULL" -ForegroundColor Gray
Write-Host "   - Apply parameter group to Aurora cluster" -ForegroundColor Gray
Write-Host "   - Reboot the cluster" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Create database and user:" -ForegroundColor White
Push-Location $terraformDir
$auroraEndpoint = terraform output -raw aurora_endpoint 2>$null
Pop-Location
if ($auroraEndpoint) {
    Write-Host "   mysql -h $auroraEndpoint -u admin -p" -ForegroundColor Gray
}
Write-Host "   CREATE DATABASE mydb;" -ForegroundColor Gray
Write-Host "   CREATE TABLE mydb.users (id INT PRIMARY KEY AUTO_INCREMENT, name VARCHAR(100), email VARCHAR(100));" -ForegroundColor Gray
Write-Host "   CREATE USER 'debezium'@'%' IDENTIFIED BY 'your-password';" -ForegroundColor Gray
Write-Host "   GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'debezium'@'%';" -ForegroundColor Gray
Write-Host ""

$auroraReady = Read-Host "Have you completed Aurora configuration? (yes/no)"
if ($auroraReady -ne 'yes') {
    Write-Host ""
    Write-Host "Please complete Aurora configuration, then run:" -ForegroundColor Yellow
    Write-Host "  .\quick-start.ps1 -SkipInfrastructure" -ForegroundColor Cyan
    Write-Host ""
    exit 0
}

# Phase 3: Connector Deployment
if (-not $SkipConnectors) {
    Write-Host ""
    Write-Host "=== Phase 3: Connector Deployment ===" -ForegroundColor Cyan
    Write-Host ""

    # Check for plugin files
    Push-Location $terraformDir
    $createConnectors = terraform output -json 2>$null | ConvertFrom-Json | Select-Object -ExpandProperty create_connectors -ErrorAction SilentlyContinue

    if (-not $createConnectors) {
        Write-Host "Note: Terraform variable 'create_connectors' is not set to true." -ForegroundColor Yellow
        Write-Host "You need to:" -ForegroundColor Yellow
        Write-Host "  1. Download connector plugin ZIPs (Debezium + JDBC)" -ForegroundColor White
        Write-Host "  2. Add to terraform.tfvars:" -ForegroundColor White
        Write-Host "     create_connectors = true" -ForegroundColor Gray
        Write-Host "     debezium_plugin_local_path = './debezium-connector.zip'" -ForegroundColor Gray
        Write-Host "     jdbc_plugin_local_path = './jdbc-sink-connector.zip'" -ForegroundColor Gray
        Write-Host "  3. Run: terraform apply" -ForegroundColor White
        Write-Host "  4. Then re-run this script with: .\quick-start.ps1 -SkipInfrastructure" -ForegroundColor White
        Write-Host ""
        Pop-Location
        exit 0
    }
    Pop-Location

    # Generate connector configs
    Write-Host "Generating connector configurations..." -ForegroundColor Yellow
    Push-Location $scriptDir
    try {
        .\generate-connector-configs.ps1
        if ($LASTEXITCODE -ne 0) {
            throw "Config generation failed"
        }
        Write-Host "✓ Configurations generated" -ForegroundColor Green
        Write-Host ""
    } catch {
        Write-Error "Failed to generate connector configs: $_"
        Pop-Location
        exit 1
    }

    # Deploy connectors
    Write-Host "Deploying connectors..." -ForegroundColor Yellow
    try {
        .\deploy-connectors.ps1 -ConnectorType all
        if ($LASTEXITCODE -ne 0) {
            throw "Connector deployment failed"
        }
        Write-Host "✓ Connectors deployed" -ForegroundColor Green
        Write-Host ""
    } catch {
        Write-Error "Failed to deploy connectors: $_"
        Pop-Location
        exit 1
    } finally {
        Pop-Location
    }
} else {
    Write-Host "=== Phase 3: Connector Deployment [SKIPPED] ===" -ForegroundColor Yellow
    Write-Host ""
}

# Success summary
Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                                                            ║" -ForegroundColor Green
Write-Host "║              Deployment Completed Successfully!            ║" -ForegroundColor Green
Write-Host "║                                                            ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "=== Next Steps ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Monitor connector status (takes 5-10 minutes):" -ForegroundColor White
Write-Host "   aws kafkaconnect list-connectors --region us-east-1" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Check CloudWatch Logs for connector activity:" -ForegroundColor White
Write-Host "   AWS Console → CloudWatch → Log Groups → /aws/mskconnect/" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Test CDC by inserting data into Aurora:" -ForegroundColor White
if ($auroraEndpoint) {
    Write-Host "   mysql -h $auroraEndpoint -u admin -p mydb" -ForegroundColor Gray
}
Write-Host "   INSERT INTO users (name, email) VALUES ('Test User', 'test@example.com');" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Verify data appears in Kafka topics and Redshift" -ForegroundColor White
Write-Host ""
Write-Host "=== Useful Commands ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Check connector status:" -ForegroundColor White
Write-Host "  aws kafkaconnect describe-connector --connector-arn <ARN>" -ForegroundColor Gray
Write-Host ""
Write-Host "View infrastructure:" -ForegroundColor White
Write-Host "  cd terraform && terraform output" -ForegroundColor Gray
Write-Host ""
Write-Host "Clean up (delete everything):" -ForegroundColor White
Write-Host "  cd terraform && terraform destroy" -ForegroundColor Gray
Write-Host ""
Write-Host "Documentation:" -ForegroundColor White
Write-Host "  See DEPLOYMENT_GUIDE.md for detailed instructions" -ForegroundColor Gray
Write-Host ""
