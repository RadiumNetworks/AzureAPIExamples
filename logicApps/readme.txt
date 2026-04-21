
.\deploy-cpu-kql.ps1 -ResourceGroupName "myRG" `
    -TargetEndpointUrl "https://your-api.example.com/api/alerts" `
    -LogAnalyticsWorkspaceId "/subscriptions/.../providers/Microsoft.OperationalInsights/workspaces/myWorkspace" `
    -LogAnalyticsWorkspaceGuid "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

Perf
| where Computer == "<vmName>"
| where ObjectName == "Processor" and CounterName == "% Processor Time" and InstanceName == "_Total"
| where TimeGenerated > ago(1h)
| project TimeGenerated, Computer, CounterValue
| order by TimeGenerated desc
| take 20


.\deploy-cpu-restart.ps1 -ResourceGroupName "myRG" `
    -TargetVmResourceId "/subscriptions/.../providers/Microsoft.Compute/virtualMachines/myVM"


.\deploy-credential-expiry.ps1 -ResourceGroupName "myRG" `
    -LogAnalyticsWorkspaceId "/subscriptions/.../providers/Microsoft.OperationalInsights/workspaces/myWorkspace" `
    -LogAnalyticsCustomerId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -LogAnalyticsWorkspaceKey "<your-shared-key>"

AppCredentialExpiry_CL
| sort by ExpirationDate_t asc
| project AppDisplayName_s, AppId_g, ObjectId_g, CredentialType_s, CredentialId_g, ExpirationDate_t, DaysUntilExpiry_d