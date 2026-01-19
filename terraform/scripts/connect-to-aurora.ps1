<#
.SYNOPSIS
Helper script to connect to Aurora MySQL via bastion host using AWS Systems Manager.

.DESCRIPTION
This script uses AWS Systems Manager Session Manager to connect to the bastion host
and then connects to Aurora MySQL from there.

.EXAMPLE
.\connect-to-aurora.ps1

.EXAMPLE
.\connect-to-aurora.ps1 -Region us-west-2
#>

param(
    [string]$Region = 'us-east-1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host @"
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║         Connect to Aurora MySQL via Bastion Host           ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$terraformDir = Resolve-Path "$scriptDir\.."

# Get Terraform outputs
Write-Host "=== Getting Infrastructure Details ===" -ForegroundColor Yellow
Push-Location $terraformDir
try {
    $bastionId = terraform output -raw bastion_instance_id 2>$null
    $auroraEndpoint = terraform output -raw aurora_endpoint 2>$null
    $dbPassword = terraform output -raw db_master_password 2>$null

    if (-not $bastionId -or $bastionId -eq "") {
        Write-Host "✗ Bastion host not found. Set create_bastion=true in terraform.tfvars and run terraform apply" -ForegroundColor Red
        exit 1
    }

    Write-Host "✓ Bastion Instance ID: $bastionId" -ForegroundColor Green
    Write-Host "✓ Aurora Endpoint: $auroraEndpoint" -ForegroundColor Green
    Write-Host ""

} catch {
    Write-Error "Failed to get Terraform outputs: $_"
    exit 1
} finally {
    Pop-Location
}

# Check if Session Manager plugin is installed
Write-Host "=== Checking AWS Session Manager Plugin ===" -ForegroundColor Yellow
try {
    $ssmCheck = session-manager-plugin 2>&1
    Write-Host "✓ Session Manager plugin is installed" -ForegroundColor Green
} catch {
    Write-Host "✗ Session Manager plugin not found" -ForegroundColor Red
    Write-Host ""
    Write-Host "Install the Session Manager plugin:" -ForegroundColor Yellow
    Write-Host "  https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html" -ForegroundColor White
    Write-Host ""
    Write-Host "Quick install (Windows):" -ForegroundColor Yellow
    Write-Host "  Invoke-WebRequest -Uri https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe -OutFile SessionManagerPluginSetup.exe" -ForegroundColor Gray
    Write-Host "  .\SessionManagerPluginSetup.exe" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

Write-Host ""

# Provide connection options
Write-Host "=== Connection Options ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Option 1: Connect via Systems Manager (Recommended)" -ForegroundColor Yellow
Write-Host "  This opens an interactive shell on the bastion host." -ForegroundColor White
Write-Host ""
Write-Host "  Command:" -ForegroundColor White
Write-Host "    `$parameters = @{" -ForegroundColor Gray
Write-Host "        'target' = '$bastionId'" -ForegroundColor Gray
Write-Host "        'region' = '$Region'" -ForegroundColor Gray
Write-Host "    }" -ForegroundColor Gray
Write-Host "    aws ssm start-session @parameters" -ForegroundColor Gray
Write-Host ""
Write-Host "  Then inside the bastion, connect to MySQL:" -ForegroundColor White
Write-Host "    mysql -h $auroraEndpoint -u admin -p'$dbPassword'" -ForegroundColor Gray
Write-Host ""
Write-Host "---" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Option 2: Direct MySQL Command via SSM" -ForegroundColor Yellow
Write-Host "  This runs the MySQL command directly." -ForegroundColor White
Write-Host ""
Write-Host "  Command:" -ForegroundColor White
Write-Host ('    aws ssm start-session --target ' + $bastionId + ' --region ' + $Region + ' --document-name AWS-StartInteractiveCommand --parameters command="mysql -h ' + $auroraEndpoint + ' -u admin -p' + "'$dbPassword'" + '"') -ForegroundColor Gray
Write-Host ""
Write-Host "---" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Option 3: SSH (if you have key pair)" -ForegroundColor Yellow
try {
    Push-Location $terraformDir
    $bastionIp = terraform output -raw bastion_public_ip 2>$null
    Pop-Location

    if ($bastionIp -and $bastionIp -ne "") {
        Write-Host "  Bastion Public IP: $bastionIp" -ForegroundColor White
        Write-Host "  Command (requires SSH key):" -ForegroundColor White
        Write-Host "    ssh -i your-key.pem ec2-user@$bastionIp" -ForegroundColor Gray
        Write-Host "    mysql -h $auroraEndpoint -u admin -p'$dbPassword'" -ForegroundColor Gray
    }
} catch {
    # Ignore error
}

Write-Host ""
Write-Host "=== Quick Setup Test ===" -ForegroundColor Cyan
Write-Host ""
$connect = Read-Host "Would you like to start an SSM session now? (yes/no)"

if ($connect -eq 'yes') {
    Write-Host ""
    Write-Host "Starting SSM session..." -ForegroundColor Yellow
    Write-Host "Once connected, run this command to connect to MySQL:" -ForegroundColor Cyan
    Write-Host "  mysql -h $auroraEndpoint -u admin -p'$dbPassword'" -ForegroundColor White
    Write-Host ""
    Write-Host "Press Ctrl+D or type 'exit' to leave the session." -ForegroundColor Gray
    Write-Host ""

    # Start SSM session
    $ssmParameters = @{
        'target' = $bastionId
        'region' = $Region
    }
    aws ssm start-session @ssmParameters
} else {
    Write-Host ""
    Write-Host "Session not started. Use the commands above when ready." -ForegroundColor Yellow
}

Write-Host ""
