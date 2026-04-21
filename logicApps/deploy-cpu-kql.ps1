param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [string]$Location = "westeurope",

    [Parameter(Mandatory = $true)]
    [string]$TargetEndpointUrl,

    [Parameter(Mandatory = $true)]
    [string]$LogAnalyticsWorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$LogAnalyticsWorkspaceGuid,

    [string]$AuthHeader = ""
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

# Deploy
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$templateFile = Join-Path $scriptDir "azuredeploy-cpu-kql.json"
Write-Host "Deploying CPU Alert + KQL enrichment Logic App..." -ForegroundColor Green

$deploymentName = "cpu-alert-kql-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$result = az deployment group create `
    --resource-group $ResourceGroupName `
    --name $deploymentName `
    --template-file $templateFile `
    --parameters targetEndpointUrl=$TargetEndpointUrl `
    --parameters logAnalyticsWorkspaceId=$LogAnalyticsWorkspaceId `
    --parameters logAnalyticsWorkspaceGuid=$LogAnalyticsWorkspaceGuid `
    --parameters targetEndpointAuthHeader=$AuthHeader `
    2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed: $result"
    exit 1
}

$output = $result | ConvertFrom-Json

Write-Host "`nDeployment succeeded!" -ForegroundColor Green
Write-Host "Logic App Callback URL (use this in Azure Monitor Action Group):" -ForegroundColor Cyan
Write-Host $output.properties.outputs.logicAppCallbackUrl.value -ForegroundColor White
Write-Host "`nLogic App Resource ID:" -ForegroundColor Cyan
Write-Host $output.properties.outputs.logicAppResourceId.value -ForegroundColor White
Write-Host "`nManaged Identity Principal ID:" -ForegroundColor Cyan
Write-Host $output.properties.outputs.logicAppPrincipalId.value -ForegroundColor White
Write-Host "`nNote: The template assigns Log Analytics Reader role to the Logic App's managed identity." -ForegroundColor Yellow
Write-Host "If the role assignment failed (e.g. insufficient permissions), assign it manually:" -ForegroundColor Yellow
Write-Host "  az role assignment create --assignee <principalId> --role 'Log Analytics Reader' --scope '$LogAnalyticsWorkspaceId'" -ForegroundColor DarkGray
