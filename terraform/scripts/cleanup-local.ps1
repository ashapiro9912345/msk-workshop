<#
Cleanup local generated files and Terraform state.

Usage:
  From the repo root:
    cd terraform
    .\scripts\cleanup-local.ps1

This script will:
- remove `connectors/generated` files
- remove local Terraform state files (`*.tfstate*`) and `.terraform` directory
#>

Set-StrictMode -Version Latest

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoDir = Resolve-Path "$scriptDir\.." | Select-Object -ExpandProperty Path

$generated = Join-Path $repoDir 'connectors\generated'
if (Test-Path $generated) {
  Write-Host "Removing generated connector files in: $generated"
  Get-ChildItem -Path $generated -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
  # Remove directory if empty
  if ((Get-ChildItem -Path $generated -Force -ErrorAction SilentlyContinue).Count -eq 0) {
    Remove-Item -Path $generated -Force -Recurse -ErrorAction SilentlyContinue
    Write-Host "Removed directory $generated"
  }
} else {
  Write-Host "No generated connector directory found at $generated"
}

# Remove local terraform state files
$tf = Join-Path $repoDir '..'
$tfFiles = Get-ChildItem -Path $tf -Include "*.tfstate*" -File -ErrorAction SilentlyContinue
foreach ($f in $tfFiles) { Remove-Item -Path $f.FullName -Force -ErrorAction SilentlyContinue; Write-Host "Removed $($f.Name)" }

# Remove .terraform directory
$dotTerraform = Join-Path $tf '.terraform'
if (Test-Path $dotTerraform) { Remove-Item -Path $dotTerraform -Recurse -Force -ErrorAction SilentlyContinue; Write-Host "Removed .terraform directory" }

Write-Host "Local cleanup complete."
