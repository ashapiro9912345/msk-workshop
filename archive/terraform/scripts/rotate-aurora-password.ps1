#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Rotates the Aurora database master password
.DESCRIPTION
    This script generates a new secure password and updates the Aurora cluster.
    You must manually update your terraform.tfvars file with the new password.
.EXAMPLE
    .\rotate-aurora-password.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "Aurora Database Password Rotation" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan
Write-Host ""

# Change to terraform directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$terraformDir = Split-Path -Parent $scriptDir
Set-Location $terraformDir

# Check if terraform is initialized
if (-not (Test-Path ".terraform")) {
    Write-Host "ERROR: Terraform not initialized. Run 'terraform init' first." -ForegroundColor Red
    exit 1
}

# Get Aurora cluster identifier
try {
    $clusterIdentifier = terraform output -raw db_cluster_identifier 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Could not get Aurora cluster identifier from Terraform output." -ForegroundColor Red
        Write-Host "Make sure Terraform has been applied successfully." -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host "ERROR: Failed to get cluster identifier: $_" -ForegroundColor Red
    exit 1
}

Write-Host "Found Aurora cluster: $clusterIdentifier" -ForegroundColor Green
Write-Host ""

# Generate a new secure password
Write-Host "Generating new secure password..." -ForegroundColor Yellow
$length = 32
$chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+[]{}|;:,.<>?"
$newPassword = -join ((1..$length) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })

Write-Host "New password generated (32 characters)" -ForegroundColor Green
Write-Host ""
Write-Host "NEW PASSWORD: $newPassword" -ForegroundColor Yellow
Write-Host ""
Write-Host "IMPORTANT: Save this password securely!" -ForegroundColor Red
Write-Host "You will need to update your terraform.tfvars file with this password." -ForegroundColor Red
Write-Host ""

# Confirm before proceeding
$confirm = Read-Host "Do you want to update the Aurora cluster password? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Password rotation cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Updating Aurora cluster password..." -ForegroundColor Yellow

# Update the Aurora cluster password using AWS CLI
try {
    aws rds modify-db-cluster `
        --db-cluster-identifier $clusterIdentifier `
        --master-user-password $newPassword `
        --apply-immediately `
        --region us-east-1

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to update Aurora cluster password." -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "Password rotation initiated successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Update terraform.tfvars with the new password:" -ForegroundColor White
    Write-Host "   db_master_password = `"$newPassword`"" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "2. Run 'terraform plan' to verify the configuration" -ForegroundColor White
    Write-Host ""
    Write-Host "3. Update any applications or scripts using the old password" -ForegroundColor White
    Write-Host ""
    Write-Host "4. The password change will take effect immediately" -ForegroundColor White
    Write-Host ""

} catch {
    Write-Host "ERROR: Failed to rotate password: $_" -ForegroundColor Red
    exit 1
}
