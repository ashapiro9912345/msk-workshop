<#
Create MSK Connect connectors from generated JSON templates.

Usage examples:
  # basic: read bootstrap from terraform outputs, role name default
  .\create-connectors.ps1 -BootstrapFromTerraform

  # provide plugin ARNs and revisions
  .\create-connectors.ps1 -BootstrapFromTerraform -DebeziumPluginArn arn:aws:... -DebeziumPluginRevision 1 -JdbcPluginArn arn:aws:... -JdbcPluginRevision 1

Notes:
- Requires AWS CLI and Terraform on PATH and authenticated AWS session.
- Expects generated connector JSONs at `..\connectors\generated\` (use inject-secrets.ps1 first).
- The script will create one connector per JSON file in that folder. JSON format expected:
  { "name": "...", "config": { ... } }
#>

param(
  [switch]$BootstrapFromTerraform,
  [string]$BootstrapServers,
  [string]$RoleName = "msk-connect-exec-role",
  [string]$ConnectorsDir = "..\connectors\generated",
  [string]$DebeziumPluginArn,
  [int]$DebeziumPluginRevision = 1,
  [string]$JdbcPluginArn,
  [int]$JdbcPluginRevision = 1,
  [int]$MCUCount = 1
)

Set-StrictMode -Version Latest

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoDir = Resolve-Path "$scriptDir\.." | Select-Object -ExpandProperty Path
$generatedDir = Join-Path $repoDir $ConnectorsDir

if (-not (Test-Path $generatedDir)) {
  Write-Error "Connectors folder not found: $generatedDir. Run inject-secrets.ps1 first to generate JSONs."
  exit 1
}

if ($BootstrapFromTerraform) {
  Push-Location $repoDir\terraform
  try {
    $bootstrap = terraform output -raw msk_bootstrap_brokers 2>$null
  } catch {
    Write-Error "Failed to read terraform output 'msk_bootstrap_brokers'. Ensure terraform init was run and outputs exist."
    Pop-Location
    exit 2
  }
  Pop-Location
  if (-not $bootstrap) { Write-Error "Bootstrap brokers empty from terraform output."; exit 3 }
} elseif ($BootstrapServers) {
  $bootstrap = $BootstrapServers
} else {
  Write-Error "Provide bootstrap servers via -BootstrapServers or set -BootstrapFromTerraform."; exit 4
}

# role ARN
try {
  $roleArn = aws iam get-role --role-name $RoleName --query 'Role.Arn' --output text 2>$null
} catch {
  Write-Error "Failed to get role ARN for role $RoleName. Ensure the role exists and AWS CLI is configured."
  exit 5
}
if (-not $roleArn) { Write-Error "Role ARN not found for $RoleName"; exit 6 }

Write-Host "Using bootstrap brokers: $bootstrap"
Write-Host "Using service role: $roleArn"

$files = Get-ChildItem -Path $generatedDir -Filter '*.json' -File
if ($files.Count -eq 0) { Write-Error "No connector JSON files found in $generatedDir"; exit 7 }

foreach ($f in $files) {
  Write-Host "Processing $($f.Name)..."
  $raw = Get-Content $f.FullName -Raw
  $o = $null
  try { $o = $raw | ConvertFrom-Json } catch { Write-Error "Invalid JSON in $($f.FullName)"; continue }
  if (-not $o.name -or -not $o.config) { Write-Error "JSON must contain 'name' and 'config' properties: $($f.FullName)"; continue }

  $connectorName = $o.name
  $configJson = ($o.config | ConvertTo-Json -Compress)

  # build plugins array if ARNs provided
  $pluginsArg = $null
  $pluginsArray = @()
  if ($DebeziumPluginArn) {
    $pluginsArray += @{ customPlugin = @{ arn = $DebeziumPluginArn; revision = "$DebeziumPluginRevision" } }
  }
  if ($JdbcPluginArn) {
    $pluginsArray += @{ customPlugin = @{ arn = $JdbcPluginArn; revision = "$JdbcPluginRevision" } }
  }
  if ($pluginsArray.Count -gt 0) {
    $pluginsArg = ($pluginsArray | ConvertTo-Json -Compress)
  }

  $kafkaCluster = @{ apacheKafka = @{ bootstrapServers = $bootstrap } }
  $kafkaClusterJson = ($kafkaCluster | ConvertTo-Json -Compress)

  $capacity = @{ provisioned = @{ mcuCount = $MCUCount } }
  $capacityJson = ($capacity | ConvertTo-Json -Compress)

  $cmd = @(
    'aws', 'mskconnect', 'create-connector',
    '--connector-name', $connectorName,
    '--kafka-cluster', $kafkaClusterJson,
    '--capacity', $capacityJson,
    '--connector-configuration', $configJson,
    '--service-execution-role-arn', $roleArn
  )

  if ($pluginsArg) { $cmd += @('--plugins', $pluginsArg) }

  Write-Host "Creating connector $connectorName ..."
  $proc = & $cmd 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create connector $connectorName. AWS CLI output:"
    Write-Error $proc
  } else {
    Write-Host "Connector create request submitted for $connectorName"
    Write-Host $proc
  }
}

Write-Host "Done."
