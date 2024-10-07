#requires -Modules 'ACME-PS', 'Az', 'AzRM.Websites', 'Az.Dns', 'Az.Keyvault'

<#PSScriptInfo
.VERSION 0.1
.TITLE Create Cert - LetsEncrypt
.AUTHOR 
.GUID 
.DESCRIPTION 
.MANUAL 
.TAGS LetsEncrypt SSL Azure
#>
<# 
  Azure Runbooks seem to have problems with ACME-PS, if Az.Storage is used as well.
  To work-around the problems, it seems neccessary to explicitly import the azure cmdlets used
  before ACME-PS is imported

    Import-Module 'Az';
    Import-Module 'Az.Storage';
    Import-Module 'Az.Websites';
    Import-Module 'ACME-PS'
#>

param(

    [Parameter(Mandatory)]
    [String] $DomainNames,

    [Parameter(Mandatory)]
    [String] $DNSSubscriptionName,

    [Parameter(Mandatory)]
    [String] $DNSResourceGroup,

    [Parameter(Mandatory)]
    [String] $DNSzone,

    [Parameter(Mandatory)]
    [String] $SubscriptionName,

    [Parameter(Mandatory)]
    [String] $ResourceGroupName,

    [Parameter(Mandatory)]
    [String] $ResourceType,

    [Parameter(Mandatory)]
    [String] $Resources,

    [Parameter(Mandatory=$false)]
    [String] $EndPoint_Listener,

    [Parameter(Mandatory=$false)]
    [String] $KeyVault,

    [Parameter()]
    [bool] $Test = $false
)

Set-StrictMode -Version Latest
Set-Item -Path Env:\AZURE_CLIENTS_SHOW_SECRETS_WARNING -Value $false

########################
# Initialize Variables
########################
$RegistrationEmail = "admin@azcloud-consulting.com" 
$VaultName = "${vault}"
$VaultSubscription = "${subscription}"
$StorageAccountName = "${sa_name}"
$StorageContainerName = "letsencrypt"
$AutomationAccountName = "${aa_name}"
$AutomationRG = "${aa_rg}"

Import-Module 'Az.Storage'
Import-Module 'ACME-PS'

# if(Get-Module 'ACME-PS'){"Module ACME-PS is loaded"}else{"Module ACME-PS is not loaded"}

###############################################################################################
## Function Add-DirectoryToStorage
###############################################################################################

function Add-DirectoryToStorage {
    Param (
        [Parameter(Mandatory=$true)]
        [string] $Path,
        [Parameter(Mandatory=$true)]
        [string] $StorageAccountName,
        [Parameter(Mandatory=$true)]
        [string] $StorageAccountKey,
        [Parameter(Mandatory=$true)]
        [string] $ContainerName
    )

    if ([string]::IsNullOrWhiteSpace($StorageAccountKey)) {
        $context = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
    }
    else {
        $context = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
    }

    $items = Get-ChildItem -Path $Path -File -Recurse
    $startIndex = $Path.Length + 1
    foreach ($item in $items) {
        $targetPath = ($item.FullName.Substring($startIndex)).Replace("\", "/")
        Set-AzStorageBlobContent -File $item.FullName -Container $ContainerName -Context $context -Blob $targetPath -Force | Out-Null
    }
}

###############################################################################################
## Function Get-DirectoryFromStorage
###############################################################################################

function Get-DirectoryFromStorage {
    Param (
        [Parameter(Mandatory=$true)]
        [string] $DestinationPath,
        [Parameter(Mandatory=$true)]
        [string] $StorageAccountName,
        [Parameter(Mandatory=$true)]
        [string] $StorageAccountKey,
        [Parameter(Mandatory=$true)]
        [string] $ContainerName,
        [Parameter()]
        [string] $BlobName
    )

    if ([string]::IsNullOrWhiteSpace($StorageAccountKey)) {
        $context = New-AzStorageContext -StorageAccountName $StorageAccountName
    }
    else {
        $context = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
    }

    if ([string]::IsNullOrWhiteSpace($BlobName)) {
        $items = Get-AzStorageBlob -Container $ContainerName -Context $context
    }
    else {
        $items = Get-AzStorageBlob -Container $ContainerName -Blob $BlobName -Context $context
    }

    if ((Test-Path $DestinationPath) -eq $FALSE) {
        New-Item -Path $DestinationPath -ItemType Directory | Out-Null
    }

    foreach ($item in $items) {
        Get-AzStorageBlobContent -Container $ContainerName -Blob $item.Name -Destination $DestinationPath -Context $context -Force | Out-Null
    }
}

###############################################################################################
## Function New-AccountProvision
###############################################################################################

function New-AccountProvisioning {
    Param (
        [Parameter(Mandatory=$True)]
        [string] $StateDir,
        [Parameter(Mandatory=$True)]
        [string[]] $ContactEmails,
        [Parameter()]
        [switch] $Test
    )

    if ($Test) {
        $serviceName = "LetsEncrypt-Staging"
    }
    else {
        $serviceName = "LetsEncrypt"
    }

    # Create a state object and save it to the harddrive
    $state = New-ACMEState -Path $StateDir

    # Fetch the service directory and save it in the state
    Get-ACMEServiceDirectory -State $state -ServiceName $serviceName

    # Get the first anti-replay nonce
    New-ACMENonce -State $state

    # Create an account key. The state will make sure it's stored.
    New-ACMEAccountKey -State $state

    # Register the account key with the acme service. The account key will automatically be read from the state
    New-ACMEAccount -State $state -EmailAddresses $ContactEmails -AcceptTOS

    return $state
}

###############################################################################################
## Function Get-SubDomainFromHostname
###############################################################################################

function Get-SubDomainFromHostname {
    Param (
        [Parameter(Mandatory=$true)]
        [string] $Hostname
    )

    $splitDomainParts = $Hostname -split "\."
    $subDomain = ""
    for ($i =0; $i -lt $splitDomainParts.Length-2; $i++) {
        $subDomain += "{0}." -f $splitDomainParts[$i]
    }
    return $subDomain.SubString(0,$subDomain.Length-1)
}

###############################################################################################
## Function Add-TxtRecordToDns
###############################################################################################

function Add-TxtRecordToDns {
    Param (
        [Parameter(Mandatory=$True)]
        [string] $ResourceGroupName,
        [Parameter(Mandatory=$True)]
        [string] $DnsZoneName,
        [Parameter(Mandatory=$True)]
        [string] $TxtName,
        [Parameter(Mandatory=$True)]
        [string] $TxtValue,
        [switch] $IsWildcard
    )

    $subDomain = Get-SubDomainFromHostname -Hostname $TxtName

    New-AzDnsRecordSet -ResourceGroupName $ResourceGroupName `
                        -ZoneName $DnsZoneName `
                        -Name $subDomain `
                        -RecordType TXT `
                        -Ttl 10 `
                        -DnsRecords (New-AzDnsRecordConfig -Value $TxtValue) `
                        -Confirm:$False `
                        -Overwrite
}

###############################################################################################
## Function Remove-TxtRecordToDns
###############################################################################################

function Remove-TxtRecordToDns {
    Param (
        [Parameter(Mandatory=$True)]
        [string] $ResourceGroupName,
        [Parameter(Mandatory=$True)]
        [string] $DnsZoneName,
        [Parameter(Mandatory=$True)]
        [string] $TxtName
    )

    $subDomain = Get-SubDomainFromHostname -Hostname $TxtName

    $recordSet = Get-AzDnsRecordSet -ResourceGroupName $ResourceGroupName `
                                    -ZoneName $DnsZoneName `
                                    -Name $subDomain `
                                    -RecordType TXT `
                                    -ErrorAction SilentlyContinue

    if ($null -ne $recordSet) {
        Remove-AzDnsRecordSet -RecordSet $recordSet -Confirm:$False -Overwrite
    }
}

##  Connect to Azure
###############################################################################################
"Logging in to Azure..."

function RunWithManagedIdentity {
    try
    {
        Connect-AzAccount -Identity
    }
    catch {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

# RunAs Account is deprecated => RunWithManagedIdentity
RunWithManagedIdentity
$AzureContext = Get-AzContext

##  Set stateDir
###############################################################################################

$mainDir = Join-Path $env:TEMP "LetsEncrypt"
if ($Test) {
    $stateDir = Join-Path $mainDir "Staging"
}
else {
    $stateDir = Join-Path $mainDir "Prod"
}
$certExportDir = Join-Path $mainDir "certificates"


##  Check Existing Certificate in Keyvault
###############################################################################################
$vaultCtx = Set-AzContext -Subscription $VaultSubscription

if ($DomainNames.Split(",").Count -gt 1 ) { 
    $DomainName = $DomainNames.Split(",")[0]
    $SanList = $DomainNames.SubString($DomainName.Length+1, $DomainNames.Length-$DomainName.Length-1)
} 
else {
    $DomainName = $DomainNames
    $SanList = ""
} 

$CertificateName = (($DomainName.Replace("*","wildcard")).Replace(".","-")).ToLowerInvariant()
if ($Test) {
    $CertificateName += "-test"
}

$ExistingCert = Get-AzKeyVaultCertificate -VaultName $VaultName -Name $CertificateName
$rawPassword =  -join (([int][char]'a'..[int][char]'z') | Get-Random -Count 20 | % { [char] $_ })
$securePassword = ConvertTo-SecureString $rawPassword -AsPlainText -Force

$ChallengeOK = $true
$SanListMatch = $false
$ExistingType = $false

if( $ExistingCert )
{
    ##  Get all information from existing Certificate
    ###############################################################################################
    $CertTags = $ExistingCert.Tags

    # Check for SAN List matching 
    $ExistingSanList=(Get-AzKeyVaultCertificatePolicy -VaultName $VaultName -Name $CertificateName).DnsNames | Where-Object { $_ -ne "$DomainName" }
    if ( $ExistingSanList ) {
        if ($SanList.Split(",").count -eq $ExistingSanList.count) {
            $SanListMatch = $true
        }
    } 
    else {
        if ($SanList -eq "") {
            $SanListMatch = $true
        }
    } 
    $ExistingType = $false
    $ResourceTypeAll=$CertTags['resource_type']
    $ResourceTypeAll.Split("|") | ForEach {
        if ( $ResourceType -eq $_ ) {
            $ExistingType = $true
        } 
    } 
    if ( $ExistingType -and $SanListMatch ) {
        Write-Warning "Certificate $CertificateName for resource type $ResourceType already exists in Vault $VaultName => Update in Resources."
    } 
    if ( -Not $ExistingType ) {
        $ResourceTypeAll += "|$ResourceType"
        $SubscriptionNameAll=$CertTags['subscription'] + "|$SubscriptionName"
        $ResourceGroupAll=$CertTags['resource_group'] + "|$ResourceGroupName"
        $ResourcesAll=$CertTags['resources'] + "|$Resources"
        $EndPoint_ListenerAll=$CertTags['endpoint_listener'] + "|$EndPoint_Listener"
        $KeyVaultAll=$CertTags['keyvault'] + "|$KeyVault"
    } 
}

"SanListMatch = $SanListMatch"
"ExistingType = $ExistingType"
if ( -Not $ExistingCert -or $ExistingType ) {
    $ResourceTypeAll = $ResourceType
    $SubscriptionNameAll = $SubscriptionName
    $ResourceGroupAll = $ResourceGroupName
    $ResourcesAll = $Resources
    $EndPoint_ListenerAll = $EndPoint_Listener
    $KeyVaultAll = $KeyVault
} 

if ( -Not $SanListMatch ) {
    $null = Set-AzContext -Subscription $DNSSubscriptionName

    ## Get previous statedir
    ###############################################################################################

    $storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $AutomationRG -Name $StorageAccountName | Where-Object { $_.KeyName -eq "key1" } | Select-Object Value).Value

    Write-Output "Fetching the state directory from storage"
    if($Test) {
        Get-DirectoryFromStorage -DestinationPath $mainDir `
                                    -StorageAccountName $StorageAccountName `
                                    -StorageAccountKey $storageAccountKey `
                                    -ContainerName $StorageContainerName `
                                    -BlobName "Staging/*"
    }
    else {
        Get-DirectoryFromStorage -DestinationPath $mainDir `
                                        -StorageAccountName $StorageAccountName `
                                        -StorageAccountKey $storageAccountKey `
                                        -ContainerName $StorageContainerName `
                                        -BlobName "Prod/*"
    }

    $isNew = (Test-Path $stateDir) -eq $false
    if ($isNew) {
        Write-Output "Directory is empty. Adding a new account"

        $state = New-AccountProvisioning -StateDir $stateDir -ContactEmails $RegistrationEmail -Test:$Test

        Write-Output "Saving the state directory to storage"
        Add-DirectoryToStorage -Path $mainDir `
                                    -StorageAccountName $StorageAccountName `
                                    -StorageAccountKey $storageAccountKey `
                                    -ContainerName $StorageContainerName
    }
    else {
        # Load an state object to have service directory and account keys available
        $state = Get-ACMEState -Path $stateDir
    }
    
    # It might be neccessary to acquire a new nonce, so we'll just do it for the sake.
    Write-Output "Acquring new nonce"
    New-ACMENonce -State $state

    $identifiers = $DomainNames.Split(",") | ForEach-Object { New-AcmeIdentifier $_ }

    ###############################################################################################
    ## Start ACME Challenge
    ###############################################################################################

    # Create a new order
    $order = New-ACMEOrder -State $state -Identifiers $identifiers

    Write-Host ($order | Format-List | Out-String)
    
    # Fetch the authorizations for that order
    $authorizations = @(Get-ACMEAuthorization -State $state -Order $order)

    foreach($authz in $authorizations) {

        # Select a challenge to fullfill
        $challenge = Get-ACMEChallenge -State $state -Authorization $authZ -Type "dns-01"

        # Inspect the challenge data (uncomment, if you want to see the object)
        # Depending on the challenge-type this will include different properties
        "Challenge Data:"
        $challenge.Data

        $challengeRecordName = $challenge.Data.TxtRecordName
        $challengeNonce      = $challenge.Data.Content
        $challengeHostName   = $challengeRecordName.Replace("." + $DNSzone, "")
        $isWildcard = $DomainName.StartsWith("*.")

        Write-Output "Adding the txt record"
        # Remove the TXT record in case it is already there
        Remove-TxtRecordToDns -ResourceGroupName $DNSResourceGroup `
                            -DnsZoneName $DNSzone `
                            -TxtName $challengeRecordName

        Add-TxtRecordToDns -ResourceGroupName $DNSResourceGroup `
                            -DnsZoneName $DNSzone `
                            -TxtName $challengeRecordName `
                            -TxtValue $challengeNonce `
                            -IsWildcard:$isWildcard

        # Wait 5 seconds for the DNS to set
        Start-Sleep -Seconds 5

        # Signal the ACME server that the challenge is ready
        $challenge | Complete-ACMEChallenge -State $state
    }

    # Wait a little bit and update the order, until we see the states
    $tries = 1
    while($order.Status -notin ("ready","invalid") -and $tries -le 3) {
        $waitTimeInSeconds = 10 * $tries
        Write-Output "Order is not ready... waiting $waitTimeInSeconds seconds"
        Start-Sleep -Seconds $waitTimeInSeconds
        $order | Update-ACMEOrder -State $state -PassThru
        $tries = $tries + 1
    }

    if ($order.Status -eq "invalid") {
        # ACME-PS as of version 1.0.7 doesn't have the error property. Fetch manually
        $authZWithError = Invoke-RestMethod -Uri $authZ.ResourceUrl
        Write-Error "Order failed. It is in invalid state. Reason: $($authZWithError.challenges.error.detail)"
        $ChallengeOK = $false
        return
    }

    if ($ChallengeOK) {
        ###############################################################################################
        ## Export certificate
        ###############################################################################################

        # We should have a valid order now and should be able to complete it, therefore we need a certificate key
        Write-Output "Grabbing the certificate key"
        $certificateKeyExportPath = Join-Path $stateDir "$DomainName.key.xml".Replace("*","wildcard")
        if (Test-Path $certificateKeyExportPath) {
            Remove-Item -Path $certificateKeyExportPath
        }
        $certKey = New-ACMECertificateKey -Path $certificateKeyExportPath

        # Complete the order - this will issue a certificate signing request
        Write-Output "Completing the order"
        # Complete-ACMEOrder -State $state -Order $order -GenerateCertificateKey;
        Complete-ACMEOrder -State $state -Order $order -CertificateKey $certKey

        # Now we wait until the ACME service provides the certificate url
        while (-not $order.CertificateUrl) {
            Start-Sleep -Seconds 15
            $order | Update-ACMEOrder -State $state -PassThru
        }

        $certIdentifier = $DomainName +"_"+"$(get-date -format yyyy-MM-dd--HH-mm)"

        New-Item $certExportDir -ItemType Directory -ea Continue
        $pfxPath = Join-Path $certExportDir $certIdentifier

        # As soon as the url shows up we can create the PFX
        Export-ACMECertificate -State $state `
            -Order $order `
            -CertificateKey $certKey `
            -Path $pfxPath `
            -Password $securePassword

        Get-Item $pfxPath

        # Remove the TXT Record
        Write-Output "Removing the TXT record"
        Remove-TxtRecordToDns -ResourceGroupName $DNSResourceGroup `
                            -DnsZoneName $DNSzone `
                            -TxtName $challengeRecordName
        
        ###############################################################################################
        ## Import du Certificat dans le Vault
        ###############################################################################################
        Write-Output "Adding the certificate to the key vault"
        $null = Set-AzContext -Subscription $VaultSubscription
        $null = Import-AzKeyVaultCertificate -VaultName $VaultName -Name $CertificateName -FilePath $pfxPath -Password $securePassword
    
        # Ajout des Tags
        $Tags = @{"dns_subscription"="$DNSSubscriptionName";"dns_resource_group"="$DNSResourceGroup";"dns_zone"="$DNSzone";"subscription"="$SubscriptionNameAll";"resource_group"="$ResourceGroupAll";"resource_type"="$ResourceTypeAll";"resources"="$ResourcesAll";"endpoint_listener"="$EndPoint_ListenerAll";"keyvault"="$KeyvaultAll"}
        $null = Update-AzKeyVaultCertificate -VaultName $VaultName -Name $CertificateName -Tag $Tags

    }
}
else {

    # Update des Tags
    $Tags = @{"dns_subscription"="$DNSSubscriptionName";"dns_resource_group"="$DNSResourceGroup";"dns_zone"="$DNSzone";"subscription"="$SubscriptionNameAll";"resource_group"="$ResourceGroupAll";"resource_type"="$ResourceTypeAll";"resources"="$ResourcesAll";"endpoint_listener"="$EndPoint_ListenerAll";"keyvault"="$KeyvaultAll"}
    $null = Update-AzKeyVaultCertificate -VaultName $VaultName -Name $CertificateName -Tag $Tags
    
}

if ($ChallengeOK) {
    $null = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext

    $params = @{"CertificateName"="$CertificateName";"DomainName"="$DomainName";"SubscriptionNameAll"="$SubscriptionNameAll";`
        "ResourceGroupAll"="$ResourceGroupAll";"ResourceTypeAll"="$ResourceTypeAll";"ResourcesAll"="$ResourcesAll";`
        "EndPoint_ListenerAll"="$EndPoint_ListenerAll";"KeyVaultAll"="$KeyVaultAll"}

    $params

    Start-AzAutomationRunbook `
        -AutomationAccountName $AutomationAccountName `
        -Name 'UploadCertToResources' `
        -ResourceGroupName $AutomationRG `
        -DefaultProfile $AzureContext `
        -Parameters $params -Wait

    Remove-Item $pfxPath

}
