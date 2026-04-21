param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [string]$Location = "westeurope",

    [Parameter(Mandatory = $true)]
    [string]$LogAnalyticsWorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$LogAnalyticsCustomerId,

    [Parameter(Mandatory = $true)]
    [string]$LogAnalyticsWorkspaceKey,

    [int]$ExpiryThresholdDays = 30,

    [string]$CustomLogTableName = "AppCredentialExpiry",

    [int]$RecurrenceHour = 7,

    [string]$LogicAppName = "credential-expiry-monitor-logicApp"
)
$ErrorActionPreference = "Stop"

# Check Azure CLI login
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Error "Not logged in to Azure CLI. Run 'az login' first."
    exit 1
}
Write-Host "Using subscription: $($account.name) ($($account.id))" -ForegroundColor Cyan

# Create resource group if needed
$rgExists = az group exists --name $ResourceGroupName | ConvertFrom-Json
if (-not $rgExists) {
    Write-Host "Creating resource group '$ResourceGroupName' in '$Location'..." -ForegroundColor Yellow
    az group create --name $ResourceGroupName --location $Location | Out-Null
}

# Deploy the Logic App
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$templateFile = Join-Path $scriptDir "azuredeploy-credential-expiry.json"
Write-Host "Deploying Credential Expiry Monitor Logic App..." -ForegroundColor Green

$deploymentName = "cred-expiry-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$result = az deployment group create `
    --resource-group $ResourceGroupName `
    --name $deploymentName `
    --template-file $templateFile `
    --parameters logicAppName=$LogicAppName `
    --parameters logAnalyticsWorkspaceId=$LogAnalyticsWorkspaceId `
    --parameters logAnalyticsCustomerId=$LogAnalyticsCustomerId `
    --parameters logAnalyticsWorkspaceKey=$LogAnalyticsWorkspaceKey `
    --parameters expiryThresholdDays=$ExpiryThresholdDays `
    --parameters customLogTableName=$CustomLogTableName `
    --parameters recurrenceHour=$RecurrenceHour `
    2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed: $result"
    exit 1
}

$output = $result | ConvertFrom-Json
$principalId = $output.properties.outputs.logicAppPrincipalId.value

Write-Host "`nDeployment succeeded!" -ForegroundColor Green
Write-Host "Logic App Resource ID:" -ForegroundColor Cyan
Write-Host $output.properties.outputs.logicAppResourceId.value -ForegroundColor White
Write-Host "`nManaged Identity Principal ID:" -ForegroundColor Cyan
Write-Host $principalId -ForegroundColor White

# Grant Microsoft Graph Application.Read.All to the managed identity
Write-Host "`n--- Granting Microsoft Graph API Permission ---" -ForegroundColor Yellow
Write-Host "The Logic App's managed identity needs 'Application.Read.All' on Microsoft Graph." -ForegroundColor White
Write-Host "This requires an admin to grant the app role assignment." -ForegroundColor White

$graphAppId = "00000003-0000-0000-c000-000000000000"  # Microsoft Graph well-known app ID
$appRoleName = "Application.Read.All"

# Get the service principal for Microsoft Graph
$graphSp = az ad sp show --id $graphAppId 2>$null | ConvertFrom-Json
if ($graphSp) {
    $appRole = ($graphSp.appRoles | Where-Object { $_.value -eq $appRoleName -and $_.allowedMemberTypes -contains "Application" })
    if ($appRole) {
        Write-Host "Assigning '$appRoleName' (role ID: $($appRole.id)) to managed identity..." -ForegroundColor Yellow

        $body = @{
            principalId = $principalId
            resourceId  = $graphSp.id
            appRoleId   = $appRole.id
        } | ConvertTo-Json -Compress

        $assignResult = az rest `
            --method POST `
            --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$principalId/appRoleAssignments" `
            --headers "Content-Type=application/json" `
            --body $body `
            2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "Graph API permission granted successfully." -ForegroundColor Green
        } else {
            Write-Warning "Could not assign Graph API permission automatically."
            Write-Host "You may need Global Admin or Privileged Role Admin rights." -ForegroundColor DarkGray
            Write-Host "Manual command:" -ForegroundColor DarkGray
            Write-Host "  az rest --method POST --uri 'https://graph.microsoft.com/v1.0/servicePrincipals/$principalId/appRoleAssignments' --body '$body'" -ForegroundColor DarkGray
        }
    }
} else {
    Write-Warning "Could not find the Microsoft Graph service principal. Grant permissions manually."
}

Write-Host "`n--- Configuration Summary ---" -ForegroundColor Cyan
Write-Host "Schedule:            Daily at ${RecurrenceHour}:00 UTC" -ForegroundColor White
Write-Host "Expiry threshold:    $ExpiryThresholdDays days" -ForegroundColor White
Write-Host "Custom log table:    ${CustomLogTableName}_CL" -ForegroundColor White
Write-Host "Workspace:           $LogAnalyticsCustomerId" -ForegroundColor White
Write-Host "`nSample KQL query to view results:" -ForegroundColor Cyan
Write-Host "  ${CustomLogTableName}_CL | sort by ExpirationDate_t asc | project AppDisplayName_s, AppId_g, ObjectId_g, CredentialType_s, CredentialId_g, ExpirationDate_t, DaysUntilExpiry_d" -ForegroundColor DarkGray
