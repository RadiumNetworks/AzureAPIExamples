param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [string]$Location = "westeurope",

    [Parameter(Mandatory = $true)]
    [string]$TargetEndpointUrl,

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
$templateFile = Join-Path $scriptDir "azuredeploy-alertforwarder.json"
Write-Host "Deploying ARM template..." -ForegroundColor Green


$deploymentName = "alert-forwarder-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$result = az deployment group create `
    --resource-group $ResourceGroupName `
    --name $deploymentName `
    --template-file $templateFile `
    --parameters targetEndpointUrl=$TargetEndpointUrl `
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
