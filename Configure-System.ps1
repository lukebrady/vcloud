$user = "someuser"
$pass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object -TypeName System.Management.Automation.PSCredential($user,$pass)

function Get-VMMetaData
{
    [CmdletBinding()]
    Param 
    (
        # Elasticsearch URI.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=1)]
        $URI
    )
    
    $vmMetaDataObj = $(Invoke-RestMethod -Method Get -Uri $URI -ErrorAction Stop)._source
    $vmMetaDataJSON = $vmMetaDataObj | ConvertTo-Json
    
    $vmMetaData = @{
        Object = $vmMetaDataObj;
        JSON = $vmMetaDataJSON
    }
    Invoke-RestMethod -Method Delete -Uri $URI -ErrorAction Stop
    return $vmMetaData       
}

function Change-NetworkSettings 
{
    [CmdletBinding()]
    Param
    (
        # Object that will used to configure network.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        $VMMetaData
    )
    
    $ifaceIndex = $(Get-NetAdapter -Name "Ethernet").ifIndex
    
    try 
    {
        New-NetIPAddress -IPAddress $VMMetaData.Object.IP_Addr `
                         -DefaultGateway $VMMetaData.Object.Gateway `
                         -InterfaceIndex $ifaceIndex 
        Set-DnsClientServerAddress -InterfaceIndex $ifaceIndex `
                                   -ServerAddresses $VMMetaData.Object.DNS_Servers
    }
    catch { $Error }   
}

function Join-Domain
{
    [CmdletBinding()]
    Param
    (
        # Domain that will be joined.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [String]
        $Domain,
        # Name that instance will be changed to.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=1)]
        [String]
        $ComputerName
    )
    
    try 
    {
        Rename-Computer -NewName $ComputerName -DomainCredential $cred -ErrorAction Continue
        Add-Computer -DomainName $Domain -Credential $cred -ErrorAction Stop -Restart
    } 
    catch { $Error }
}