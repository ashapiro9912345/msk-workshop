<#
Inject secrets from `secrets.auto.tfvars` into connector JSON templates.

Usage:
  .\inject-secrets.ps1

This script reads `../secrets.auto.tfvars` for `db_master_password` and `redshift_master_password`,
replaces placeholder tokens in the templates under `..\connectors\` and writes final files to
`..\connectors\generated\` (created if missing).

Do NOT commit the generated files if they contain secrets.
#>

Param()

Set-StrictMode -Version Latest

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoTerraformDir = Resolve-Path "$scriptDir\.."
$secretsFile = Join-Path $repoTerraformDir 'secrets.auto.tfvars'
$connectorsDir = Join-Path $repoTerraformDir 'connectors'
$outDir = Join-Path $connectorsDir 'generated'

if (-not (Test-Path $secretsFile)) {
  Write-Error "secrets.auto.tfvars not found at $secretsFile"
  exit 1
}

$content = Get-Content $secretsFile -Raw

function Get-Var($name) {
  $pattern = '(?m)^{0}\s*=\s+"(?<val>.*)"' -f [regex]::Escape($name)
  $m = [regex]::Match($content, $pattern)
  if ($m.Success) { return $m.Groups['val'].Value }
  return $null
}

$dbPassword = Get-Var 'db_master_password'
$rsPassword = Get-Var 'redshift_master_password'

if (-not $dbPassword -or -not $rsPassword) {
  Write-Error "Could not find required secrets in $secretsFile. Ensure variables exist and are quoted strings."
  exit 2
}

if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

$templates = Get-ChildItem -Path $connectorsDir -Filter '*.json' -File | Where-Object { $_.DirectoryName -ne $outDir }

foreach ($t in $templates) {
  $text = Get-Content $t.FullName -Raw

  # Replace known placeholders with JSON-escaped secrets
  $dbJson = $dbPassword | ConvertTo-Json -Compress
  $dbEscaped = $dbJson.Substring(1, $dbJson.Length - 2)
  $rsJson = $rsPassword | ConvertTo-Json -Compress
  $rsEscaped = $rsJson.Substring(1, $rsJson.Length - 2)

  $text = $text -replace 'REPLACE_WITH_DB_MASTER_OR_REPL_PASSWORD', $dbEscaped
  $text = $text -replace 'REPLACE_WITH_REDSHIFT_PASSWORD', $rsEscaped

  $outPath = Join-Path $outDir $t.Name
  Set-Content -Path $outPath -Value $text -Encoding UTF8
  Write-Host "Wrote $outPath"
}

Write-Host "Done. Generated connector files are in: $outDir"
