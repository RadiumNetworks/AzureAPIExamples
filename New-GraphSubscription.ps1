$AppId = ""
$TenantId = ""
$TenantName = ""

$Certificate = (Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*toARC" } | Sort-Object -Property NotAfter -Descending)[0]
$Scope = "https://graph.microsoft.com/.default"

# Create base64 hash of certificate
$CertificateBase64Hash = [System.Convert]::ToBase64String($Certificate.GetCertHash())

# Create JWT timestamp for expiration
$StartDate = (Get-Date "1970-01-01T00:00:00Z").ToUniversalTime()
$JWTExpirationTimeSpan = (New-TimeSpan -Start $StartDate -End (Get-Date).ToUniversalTime().AddMinutes(2)).TotalSeconds
$JWTExpiration = [math]::Round($JWTExpirationTimeSpan, 0)

# Create JWT validity start timestamp
$NotBeforeExpirationTimeSpan = (New-TimeSpan -Start $StartDate -End ((Get-Date).ToUniversalTime())).TotalSeconds
$NotBefore = [math]::Round($NotBeforeExpirationTimeSpan, 0)

# Create JWT header
$JWTHeader = @{
    alg = "RS256"
    typ = "JWT"
    x5t = $CertificateBase64Hash -replace '\+', '-' -replace '/', '_' -replace '='
}

# Create JWT payload
$JWTPayLoad = @{
    aud = "https://login.microsoftonline.com/$TenantName/oauth2/token"
    exp = $JWTExpiration
    iss = $AppId
    jti = [guid]::NewGuid()
    nbf = $NotBefore
    sub = $AppId
}

# Convert header and payload to base64
$JWTHeaderToByte = [System.Text.Encoding]::UTF8.GetBytes(($JWTHeader | ConvertTo-Json))
$EncodedHeader = [System.Convert]::ToBase64String($JWTHeaderToByte)

$JWTPayLoadToByte = [System.Text.Encoding]::UTF8.GetBytes(($JWTPayload | ConvertTo-Json))
$EncodedPayload = [System.Convert]::ToBase64String($JWTPayLoadToByte)

# Join header and payload with "." to create a valid (unsigned) JWT
$JWT = $EncodedHeader + "." + $EncodedPayload

# Get the private key object of your certificate
$PrivateKey = ([System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate))

# Define RSA signature and hashing algorithm
$RSAPadding = [Security.Cryptography.RSASignaturePadding]::Pkcs1
$HashAlgorithm = [Security.Cryptography.HashAlgorithmName]::SHA256

# Create a signature of the JWT
$Signature = [Convert]::ToBase64String(
    $PrivateKey.SignData([System.Text.Encoding]::UTF8.GetBytes($JWT), $HashAlgorithm, $RSAPadding)
) -replace '\+', '-' -replace '/', '_' -replace '='

# Join the signature to the JWT with "."
$JWT = $JWT + "." + $Signature

# Create body parameters for token request
$Body = @{
    client_id             = $AppId
    client_assertion      = $JWT
    client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
    scope                 = $Scope
    grant_type            = "client_credentials"
}

$Url = "https://login.microsoftonline.com/$TenantName/oauth2/v2.0/token"

$Header = @{
    Authorization = "Bearer $JWT"
}

$PostSplat = @{
    ContentType = 'application/x-www-form-urlencoded'
    Method      = 'POST'
    Body        = $Body
    Uri         = $Url
    Headers     = $Header
}

$bearerToken = (Invoke-RestMethod @PostSplat).access_token




$GraphBaseUri = "https://graph.microsoft.com/v1.0"
$Headers = @{
    Authorization  = "Bearer $bearerToken"
    'Content-Type' = 'application/json'
}


$SubscriptionBody = @{
    changeType         = "created,updated,deleted"
    notificationUrl    = "https://graphnotificationapi-ehhgaabdcya4beg8.westeurope-01.azurewebsites.net/api/notifications"
    resource           = "/users"
    expirationDateTime = (Get-Date).ToUniversalTime().AddMinutes(4230).ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")
    clientState        = [guid]::NewGuid().ToString()
} | ConvertTo-Json

Write-Host "Creating subscription for /users changes..."

try 
{
    $Subscription = Invoke-RestMethod `
        -Method POST `
        -Uri "$GraphBaseUri/subscriptions" `
        -Headers $Headers `
        -Body $SubscriptionBody

    Write-Host "Subscription created successfully:"
    Write-Host "  Id:         $($Subscription.id)"
    Write-Host "  Resource:   $($Subscription.resource)"
    Write-Host "  ChangeType: $($Subscription.changeType)"
    Write-Host "  Expires:    $($Subscription.expirationDateTime)"
}
catch
{
    Write-Host "Subscription creation failed:"

}

function Get-GraphSubscriptions {
    Invoke-RestMethod -Method GET -Uri "$GraphBaseUri/subscriptions" -Headers $Headers
}

function Update-GraphSubscription {
    param(
        [Parameter(Mandatory)]
        [string]$SubscriptionId,

        [int]$ExtendMinutes = 4230
    )

    $RenewBody = @{
        expirationDateTime = (Get-Date).ToUniversalTime().AddMinutes($ExtendMinutes).ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")
    } | ConvertTo-Json

    Invoke-RestMethod `
        -Method PATCH `
        -Uri "$GraphBaseUri/subscriptions/$SubscriptionId" `
        -Headers $Headers `
        -Body $RenewBody
}

function Remove-GraphSubscription {
    param(
        [Parameter(Mandatory)]
        [string]$SubscriptionId
    )

    Invoke-RestMethod `
        -Method DELETE `
        -Uri "$GraphBaseUri/subscriptions/$SubscriptionId" `
        -Headers $Headers
}
