if ( !(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) ) {
. “C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1”
}

$user = "someuser"
$pass = ConvertTo-SecureString "password" -AsPlainText -Force
$cred = New-Object -TypeName System.Management.Automation.PSCredential($user,$pass)
Connect-VIServer -Server $server -Credential $cred

function Get-LeastLoadedDataStore 
{
    $datastores = Get-Datastore
    
    $spaceObject = $datastores.FreeSpaceGB | Sort-Object
    $leastFreeSpace = $spaceObject[$spaceObject.Length - 1]
    $leastLoaded = @{}

    foreach($datastore in $datastores) 
    {
        try
        {
            if($datastore.FreeSpaceGB -eq $leastFreeSpace)
            {
                $leastLoaded.Add($datastore.Name,$leastFreeSpace)
            } 
         } 
         catch { $Error }   
    }

    return $leastLoaded
}

function Get-DCMetaData 
{
    $datacenter = Get-Datacenter
    $hosts = $(Get-VMHost).Name
    $templates = Get-Template
    $memory = $(Get-ResourcePool).MemReservationGB

    $dcMetaData = @{
        "Datacenter" = $datacenter;
        "Hosts" = $hosts;
        "Templates" = $templates;
        "Memory" = $memory;
    }

    return $dcMetaData
}

function Document-Deployment
{
    [CmdletBinding()]
    Param
    (
        # Object of MetaData collected by Get-DCMetaData
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        $MetaDataObject,
        [String]
        $OutputPath,
        # ElasticSearch instance to send documentation.
        [String]
        $ElasticSearchURI
    )
    

}

function New-VMFromTemplate
{
    [CmdletBinding()]
    Param
    (
        # JSON template path.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        $Template
    )

    $templateObject = Get-Content -Path $Template | ConvertFrom-Json -Verbose
    $name = $($templateObject.Name).toUpper()
    $datastore = Get-LeastLoadedDataStore
    
    if($(Get-VM $name) -eq $null) 
    {
        New-VM -Name $name `
               -Template $templateObject.Template `
               -ResourcePool $templateObject.Resource_Pool `
               -Datastore $templateObject.Datastore
        try
        {
            $(Get-VM $name).PowerState -eq "PoweredOn"
            Write-Host "The VM, $name is already powered on."
        }
        catch 
        {
            Write-Host "Powering on $name."
            Start-VM -VM $name
        }
    }
    else 
    {
        Write-Output "This VM has already been provisioned."
        try
        {
            $(Get-VM $name).PowerState -eq "PoweredOn"
            Write-Host "The VM, $name is already powered on."
        }
        catch
        {
            Write-Host "Powering on $name."
            Start-VM -VM $name
        }
    }

    return $templateObject
}

function Set-VMMetaData 
{
    [CmdletBinding()]
    Param 
    (
        # JSON template path.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        $VMTemplateObject,
        # Elasticsearch URI.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=1)]
        $URI
     )
     $uploadTime = Get-Date -UFormat %H:%M:%S
     $vmMetaDataObj = @{
        Name = $VMTemplateObject.name.toUpper();
        IP_Addr = $VMTemplateObject.args.ip_addr;
        Netmask = $VMTemplateObject.args.netmask;
        Gateway = $VMTemplateObject.args.gateway;
        DNS_Servers = $VMTemplateObject.args.dns_servers;
        Domain = $VMTemplateObject.args.domain;
        Upload_Time = $uploadTime;   
     }

     $vmMetaDataJSON = $vmMetaDataObj | ConvertTo-Json -ErrorAction Stop
     $vmMetaDataJSON
     Invoke-RestMethod -Method Post -Uri $URI -Body $vmMetaDataJSON -ErrorAction Stop
}

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
    
    return $vmMetaData       
}