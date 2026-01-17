<#
.SYNOPSIS
Generate MSK Connect connector configurations from Terraform outputs and secrets.

.DESCRIPTION
This script reads Terraform outputs and secrets.auto.tfvars, then generates
fully configured connector JSON files ready for deployment. Generated files
are written to connectors/generated/ directory.

.EXAMPLE
.\generate-connector-configs.ps1

.NOTES
Requires: Terraform state with applied infrastructure, secrets.auto.tfvars file
#>

param(
    [string]$TerraformDir = "..",
    [string]$SecretsFile = "..\secrets.auto.tfvars",
    [string]$ConnectorsDir = "..\connectors",
    [string]$OutputDir = "..\connectors\generated"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== MSK Connect Configuration Generator ===" -ForegroundColor Cyan
Write-Host ""

# Validate paths
$TerraformDir = Resolve-Path $TerraformDir
$SecretsFile = Join-Path $TerraformDir "secrets.auto.tfvars"
$ConnectorsDir = Join-Path $TerraformDir "connectors"
$OutputDir = Join-Path $ConnectorsDir "generated"

if (-not (Test-Path $SecretsFile)) {
    Write-Error "secrets.auto.tfvars not found at: $SecretsFile"
    exit 1
}

if (-not (Test-Path $ConnectorsDir)) {
    Write-Error "Connectors directory not found at: $ConnectorsDir"
    exit 1
}

# Create output directory
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
    Write-Host "Created output directory: $OutputDir" -ForegroundColor Green
}

# Parse secrets from tfvars file
Write-Host "Reading secrets from: $SecretsFile" -ForegroundColor Yellow
$secretsContent = Get-Content $SecretsFile -Raw

function Get-TfVar($name, $content) {
    $pattern = '(?m)^{0}\s*=\s*"(?<val>[^"]*)"' -f [regex]::Escape($name)
    $m = [regex]::Match($content, $pattern)
    if ($m.Success) {
        return $m.Groups['val'].Value
    }
    return $null
}

$dbPassword = Get-TfVar 'db_master_password' $secretsContent
$redshiftPassword = Get-TfVar 'redshift_master_password' $secretsContent

if (-not $dbPassword) {
    Write-Error "Could not find 'db_master_password' in $SecretsFile"
    exit 1
}

Write-Host "✓ Loaded secrets" -ForegroundColor Green
Write-Host ""

# Get Terraform outputs
Write-Host "Reading Terraform outputs..." -ForegroundColor Yellow
Push-Location $TerraformDir

try {
    $mskBootstrap = terraform output -raw msk_bootstrap_brokers 2>$null
    $auroraEndpoint = terraform output -raw aurora_endpoint 2>$null
    $redshiftEndpoint = terraform output -raw redshift_endpoint 2>$null
    $vpcId = terraform output -raw vpc_id 2>$null
} catch {
    Write-Error "Failed to read Terraform outputs. Ensure 'terraform apply' has been run successfully."
    Pop-Location
    exit 1
} finally {
    Pop-Location
}

if (-not $mskBootstrap) {
    Write-Error "MSK bootstrap brokers output is empty. Run 'terraform apply' first."
    exit 1
}

if (-not $auroraEndpoint) {
    Write-Error "Aurora endpoint output is empty. Run 'terraform apply' first."
    exit 1
}

Write-Host "✓ MSK Bootstrap: $mskBootstrap" -ForegroundColor Green
Write-Host "✓ Aurora Endpoint: $auroraEndpoint" -ForegroundColor Green
if ($redshiftEndpoint) {
    Write-Host "✓ Redshift Endpoint: $redshiftEndpoint" -ForegroundColor Green
} else {
    Write-Host "! Redshift not deployed (create_redshift=false)" -ForegroundColor Yellow
}
Write-Host ""

# Generate Debezium source connector config
Write-Host "Generating Debezium MySQL source connector config..." -ForegroundColor Yellow

$debeziumConfig = @{
    name = "debezium-aurora-mysql-source"
    config = @{
        "connector.class" = "io.debezium.connector.mysql.MySqlConnector"
        "tasks.max" = "1"
        "database.hostname" = $auroraEndpoint
        "database.port" = "3306"
        "database.user" = "debezium"
        "database.password" = $dbPassword
        "database.server.id" = "184054"
        "database.server.name" = "aurora_mysql_cdc"
        "database.include.list" = "mydb"
        "table.include.list" = "mydb.users"
        "include.schema.changes" = "false"
        "database.history.kafka.bootstrap.servers" = $mskBootstrap
        "database.history.kafka.topic" = "schema-changes.aurora"
        "schema.history.internal.kafka.bootstrap.servers" = $mskBootstrap
        "schema.history.internal.kafka.topic" = "schema-changes.aurora"
        "topic.prefix" = "aurora"
        "snapshot.mode" = "initial"
        "decimal.handling.mode" = "double"
        "time.precision.mode" = "adaptive"
        "bigint.unsigned.handling.mode" = "long"
    }
}

$debeziumJson = $debeziumConfig | ConvertTo-Json -Depth 10
$debeziumPath = Join-Path $OutputDir "debezium-aurora-mysql-source.json"
Set-Content -Path $debeziumPath -Value $debeziumJson -Encoding UTF8
Write-Host "✓ Created: $debeziumPath" -ForegroundColor Green

# Generate JDBC sink connector config (if Redshift exists)
if ($redshiftEndpoint) {
    Write-Host "Generating JDBC Redshift sink connector config..." -ForegroundColor Yellow

    # Extract hostname from endpoint (remove port if present)
    $redshiftHost = $redshiftEndpoint -replace ':\d+$', ''
    $connectionUrl = "jdbc:redshift://${redshiftEndpoint}/dev?user=rsadmin&password=${redshiftPassword}"

    $jdbcConfig = @{
        name = "redshift-jdbc-sink"
        config = @{
            "connector.class" = "io.confluent.connect.jdbc.JdbcSinkConnector"
            "tasks.max" = "1"
            "topics" = "aurora.mydb.users"
            "connection.url" = $connectionUrl
            "auto.create" = "true"
            "auto.evolve" = "true"
            "insert.mode" = "upsert"
            "pk.mode" = "record_key"
            "pk.fields" = "id"
            "table.name.format" = "users"
            "delete.enabled" = "true"
        }
    }

    $jdbcJson = $jdbcConfig | ConvertTo-Json -Depth 10
    $jdbcPath = Join-Path $OutputDir "redshift-jdbc-sink.json"
    Set-Content -Path $jdbcPath -Value $jdbcJson -Encoding UTF8
    Write-Host "✓ Created: $jdbcPath" -ForegroundColor Green
} else {
    Write-Host "⊗ Skipping Redshift connector (Redshift not deployed)" -ForegroundColor Yellow
}

# Generate connector deployment manifest
Write-Host ""
Write-Host "Generating deployment manifest..." -ForegroundColor Yellow

$manifest = @{
    generated_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    infrastructure = @{
        vpc_id = $vpcId
        msk_bootstrap_brokers = $mskBootstrap
        aurora_endpoint = $auroraEndpoint
        redshift_endpoint = $redshiftEndpoint
    }
    connectors = @{
        debezium = @{
            config_file = "debezium-aurora-mysql-source.json"
            description = "CDC from Aurora MySQL to MSK"
            topics_created = @("aurora.mydb.users")
        }
    }
    notes = @(
        "These configuration files contain sensitive credentials",
        "DO NOT commit files in the generated/ directory to version control",
        "Use deploy-connectors.ps1 script to deploy these configurations"
    )
}

if ($redshiftEndpoint) {
    $manifest.connectors.jdbc = @{
        config_file = "redshift-jdbc-sink.json"
        description = "Sink from MSK to Redshift"
        topics_consumed = @("aurora.mydb.users")
    }
}

$manifestJson = $manifest | ConvertTo-Json -Depth 10
$manifestPath = Join-Path $OutputDir "deployment-manifest.json"
Set-Content -Path $manifestPath -Value $manifestJson -Encoding UTF8
Write-Host "✓ Created: $manifestPath" -ForegroundColor Green

Write-Host ""
Write-Host "=== Configuration Generation Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Generated files:" -ForegroundColor Cyan
Write-Host "  - $debeziumPath"
if ($redshiftEndpoint) {
    Write-Host "  - $jdbcPath"
}
Write-Host "  - $manifestPath"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Review the generated configuration files"
Write-Host "  2. Ensure Aurora has binary logging enabled"
Write-Host "  3. Create 'debezium' user in Aurora with replication privileges"
Write-Host "  4. Run: .\deploy-connectors.ps1 to deploy connectors"
Write-Host ""
Write-Host "WARNING: Generated files contain passwords. DO NOT commit to git!" -ForegroundColor Red
