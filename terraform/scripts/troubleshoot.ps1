<#
.SYNOPSIS
Troubleshooting helper for MSK Workshop deployment.

.DESCRIPTION
This script checks the status of all components and provides diagnostic information.

.EXAMPLE
.\troubleshoot.ps1
#>

param(
    [string]$Region = 'us-east-1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host @"
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║          MSK Workshop Troubleshooting Tool                 ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$terraformDir = Resolve-Path "$scriptDir\.."

# Check 1: Terraform State
Write-Host "=== Terraform State ===" -ForegroundColor Yellow
Push-Location $terraformDir
try {
    $stateResources = terraform state list 2>$null
    if ($stateResources) {
        $resourceCount = ($stateResources | Measure-Object).Count
        Write-Host "✓ Terraform state exists: $resourceCount resources" -ForegroundColor Green

        # Get outputs
        Write-Host ""
        Write-Host "Infrastructure Outputs:" -ForegroundColor Cyan
        $outputs = terraform output -json 2>$null | ConvertFrom-Json
        if ($outputs) {
            Write-Host "  VPC ID: $($outputs.vpc_id.value)" -ForegroundColor White
            Write-Host "  MSK Brokers: $($outputs.msk_bootstrap_brokers.value)" -ForegroundColor White
            Write-Host "  Aurora: $($outputs.aurora_endpoint.value)" -ForegroundColor White
            if ($outputs.redshift_endpoint.value) {
                Write-Host "  Redshift: $($outputs.redshift_endpoint.value)" -ForegroundColor White
            }
        }
    } else {
        Write-Host "✗ No Terraform state found. Run 'terraform apply' first." -ForegroundColor Red
    }
} catch {
    Write-Host "✗ Error reading Terraform state: $_" -ForegroundColor Red
} finally {
    Pop-Location
}

Write-Host ""

# Check 2: MSK Cluster
Write-Host "=== MSK Cluster ===" -ForegroundColor Yellow
try {
    $listClustersParams = @{
        'region' = $Region
    }
    $clusters = aws kafka list-clusters @listClustersParams 2>&1 | ConvertFrom-Json
    if ($clusters.ClusterInfoList.Count -gt 0) {
        foreach ($cluster in $clusters.ClusterInfoList) {
            $state = $cluster.State
            $color = if ($state -eq "ACTIVE") { "Green" } else { "Yellow" }
            Write-Host "✓ Cluster: $($cluster.ClusterName) - State: $state" -ForegroundColor $color
            Write-Host "  ARN: $($cluster.ClusterArn)" -ForegroundColor Gray
        }
    } else {
        Write-Host "✗ No MSK clusters found" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ Error checking MSK: $_" -ForegroundColor Red
}

Write-Host ""

# Check 3: Aurora Cluster
Write-Host "=== Aurora Cluster ===" -ForegroundColor Yellow
try {
    $describeClustersParams = @{
        'region' = $Region
    }
    $dbClusters = aws rds describe-db-clusters @describeClustersParams 2>&1 | ConvertFrom-Json
    $auroraClusters = $dbClusters.DBClusters | Where-Object { $_.DBClusterIdentifier -like "*aurora*" -or $_.DBClusterIdentifier -like "*cdc*" }

    if ($auroraClusters) {
        foreach ($cluster in $auroraClusters) {
            $status = $cluster.Status
            $color = if ($status -eq "available") { "Green" } else { "Yellow" }
            Write-Host "✓ Cluster: $($cluster.DBClusterIdentifier) - Status: $status" -ForegroundColor $color
            Write-Host "  Endpoint: $($cluster.Endpoint)" -ForegroundColor Gray
            Write-Host "  Engine: $($cluster.Engine) $($cluster.EngineVersion)" -ForegroundColor Gray

            # Check parameter group
            $paramGroup = $cluster.DBClusterParameterGroup
            Write-Host "  Parameter Group: $paramGroup" -ForegroundColor Gray

            # Try to check binlog settings
            try {
                $paramGroupParams = @{
                    'db-cluster-parameter-group-name' = $paramGroup
                    'region'                          = $Region
                    'query'                           = "Parameters[?ParameterName=='binlog_format' || ParameterName=='binlog_row_image'].[ParameterName,ParameterValue]"
                    'output'                          = 'table'
                }
                $params = aws rds describe-db-cluster-parameters @paramGroupParams 2>$null

                if ($params) {
                    Write-Host "  Binary Logging Configuration:" -ForegroundColor Cyan
                    Write-Host $params -ForegroundColor Gray
                } else {
                    Write-Host "  ⚠ Could not verify binary logging settings" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "  ⚠ Could not check parameter group settings" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "✗ No Aurora clusters found" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ Error checking Aurora: $_" -ForegroundColor Red
}

Write-Host ""

# Check 4: Redshift Cluster
Write-Host "=== Redshift Cluster ===" -ForegroundColor Yellow
try {
    $describeRedshiftParams = @{
        'region' = $Region
    }
    $rsClusters = aws redshift describe-clusters @describeRedshiftParams 2>&1 | ConvertFrom-Json
    if ($rsClusters.Clusters.Count -gt 0) {
        foreach ($cluster in $rsClusters.Clusters) {
            $status = $cluster.ClusterStatus
            $color = if ($status -eq "available") { "Green" } else { "Yellow" }
            Write-Host "✓ Cluster: $($cluster.ClusterIdentifier) - Status: $status" -ForegroundColor $color
            Write-Host "  Endpoint: $($cluster.Endpoint.Address):$($cluster.Endpoint.Port)" -ForegroundColor Gray
        }
    } else {
        Write-Host "⊗ No Redshift clusters (create_redshift=false)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⊗ No Redshift clusters or error checking" -ForegroundColor Yellow
}

Write-Host ""

# Check 5: MSK Connect Plugins
Write-Host "=== MSK Connect Custom Plugins ===" -ForegroundColor Yellow
try {
    $listPluginsParams = @{
        'region' = $Region
    }
    $plugins = aws kafkaconnect list-custom-plugins @listPluginsParams 2>&1 | ConvertFrom-Json
    if ($plugins.customPlugins.Count -gt 0) {
        foreach ($plugin in $plugins.customPlugins) {
            $state = $plugin.customPluginState
            $color = if ($state -eq "ACTIVE") { "Green" } else { "Yellow" }
            Write-Host "✓ Plugin: $($plugin.name) - State: $state" -ForegroundColor $color
            Write-Host "  ARN: $($plugin.customPluginArn)" -ForegroundColor Gray
            Write-Host "  Revision: $($plugin.latestRevision.revision)" -ForegroundColor Gray
        }
    } else {
        Write-Host "✗ No custom plugins found. Set create_connectors=true and apply Terraform." -ForegroundColor Red
    }
} catch {
    Write-Host "✗ Error checking plugins: $_" -ForegroundColor Red
}

Write-Host ""

# Check 6: MSK Connect Connectors
Write-Host "=== MSK Connect Connectors ===" -ForegroundColor Yellow
try {
    $listConnectorsParams = @{
        'region' = $Region
    }
    $connectors = aws kafkaconnect list-connectors @listConnectorsParams 2>&1 | ConvertFrom-Json
    if ($connectors.connectors.Count -gt 0) {
        foreach ($connector in $connectors.connectors) {
            $state = $connector.connectorState
            $color = switch ($state) {
                "RUNNING" { "Green" }
                "CREATING" { "Yellow" }
                "FAILED" { "Red" }
                default { "White" }
            }
            Write-Host "• Connector: $($connector.connectorName) - State: $state" -ForegroundColor $color
            Write-Host "  ARN: $($connector.connectorArn)" -ForegroundColor Gray

            # Get detailed info
            try {
                $describeConnectorParams = @{
                    'connector-arn' = $connector.connectorArn
                    'region'        = $Region
                }
                $detail = aws kafkaconnect describe-connector @describeConnectorParams 2>&1 | ConvertFrom-Json
                if ($detail.connectorDescription) {
                    $desc = $detail.connectorDescription
                    Write-Host "  Created: $($desc.creationTime)" -ForegroundColor Gray

                    if ($desc.stateDescription) {
                        Write-Host "  State Description: $($desc.stateDescription.message)" -ForegroundColor Gray
                    }

                    # Show log group
                    $logGroup = "/aws/mskconnect/$($connector.connectorName)"
                    Write-Host "  Logs: $logGroup" -ForegroundColor Gray
                }
            } catch {
                Write-Host "  ⚠ Could not get detailed info" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "✗ No connectors found. Run deploy-connectors.ps1 to create them." -ForegroundColor Red
    }
} catch {
    Write-Host "✗ Error checking connectors: $_" -ForegroundColor Red
}

Write-Host ""

# Check 7: IAM Role
Write-Host "=== IAM Role ===" -ForegroundColor Yellow
try {
    $getRoleParams = @{
        'role-name' = 'msk-connect-exec-role'
        'region'    = $Region
    }
    $role = aws iam get-role @getRoleParams 2>&1 | ConvertFrom-Json
    if ($role.Role) {
        Write-Host "✓ Role exists: msk-connect-exec-role" -ForegroundColor Green
        Write-Host "  ARN: $($role.Role.Arn)" -ForegroundColor Gray

        # Check attached policies
        $listPoliciesParams = @{
            'role-name' = 'msk-connect-exec-role'
        }
        $policies = aws iam list-attached-role-policies @listPoliciesParams 2>&1 | ConvertFrom-Json
        Write-Host "  Attached Policies:" -ForegroundColor Gray
        foreach ($policy in $policies.AttachedPolicies) {
            Write-Host "    - $($policy.PolicyName)" -ForegroundColor Gray
        }
    }
} catch {
    Write-Host "✗ IAM role not found" -ForegroundColor Red
}

Write-Host ""

# Check 8: CloudWatch Log Groups
Write-Host "=== CloudWatch Log Groups ===" -ForegroundColor Yellow
try {
    $describeLogGroupsParams = @{
        'region'                 = $Region
        'log-group-name-prefix'  = '/aws/mskconnect'
    }
    $logGroups = aws logs describe-log-groups @describeLogGroupsParams 2>&1 | ConvertFrom-Json
    if ($logGroups.logGroups.Count -gt 0) {
        foreach ($lg in $logGroups.logGroups) {
            Write-Host "✓ Log Group: $($lg.logGroupName)" -ForegroundColor Green

            # Check for recent logs
            $logStreamsParams = @{
                'log-group-name' = $lg.logGroupName
                'region'         = $Region
                'order-by'       = 'LastEventTime'
                'descending'     = $true
                'max-items'      = '1'
            }
            $streams = aws logs describe-log-streams @logStreamsParams 2>&1 | ConvertFrom-Json

            if ($streams.logStreams.Count -gt 0) {
                $lastEvent = [DateTimeOffset]::FromUnixTimeMilliseconds($streams.logStreams[0].lastEventTimestamp).LocalDateTime
                Write-Host "  Last Activity: $lastEvent" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "⊗ No connector log groups found" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⊗ No log groups or error checking" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Recommendations ===" -ForegroundColor Cyan
Write-Host ""

# Provide recommendations based on findings
$recommendations = @()

# Check if infrastructure exists
Push-Location $terraformDir
$hasState = (terraform state list 2>$null | Measure-Object).Count -gt 0
Pop-Location

if (-not $hasState) {
    $recommendations += "• Run 'terraform apply' to deploy infrastructure"
}

# Check if plugins exist
$pluginCount = 0
try {
    $pluginsCheckParams = @{
        'region' = $Region
    }
    $pluginsCheck = aws kafkaconnect list-custom-plugins @pluginsCheckParams 2>&1 | ConvertFrom-Json
    $pluginCount = $pluginsCheck.customPlugins.Count
} catch {}

if ($pluginCount -eq 0) {
    $recommendations += "• Set 'create_connectors=true' in terraform.tfvars"
    $recommendations += "• Download connector plugin ZIPs and configure paths"
    $recommendations += "• Run 'terraform apply' to create plugins"
}

# Check if connectors exist
$connectorCount = 0
try {
    $listConnectorsCheckParams = @{
        'region' = $Region
    }
    $connectorsCheck = aws kafkaconnect list-connectors @listConnectorsCheckParams 2>&1 | ConvertFrom-Json
    $connectorCount = $connectorsCheck.connectors.Count
} catch {}

if ($connectorCount -eq 0 -and $pluginCount -gt 0) {
    $recommendations += "• Run '.\generate-connector-configs.ps1' to create configs"
    $recommendations += "• Run '.\deploy-connectors.ps1' to deploy connectors"
}

if ($recommendations.Count -gt 0) {
    foreach ($rec in $recommendations) {
        Write-Host $rec -ForegroundColor Yellow
    }
} else {
    Write-Host "✓ All components appear to be deployed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "To verify data flow:" -ForegroundColor Yellow
    Write-Host "  1. Insert data into Aurora MySQL" -ForegroundColor White
    Write-Host "  2. Check connector logs in CloudWatch" -ForegroundColor White
    Write-Host "  3. Verify data in Redshift (if enabled)" -ForegroundColor White
}

Write-Host ""
Write-Host "For detailed logs, check CloudWatch:" -ForegroundColor Cyan
Write-Host "  https://console.aws.amazon.com/cloudwatch/home?region=$Region#logsV2:log-groups" -ForegroundColor Gray
Write-Host ""
