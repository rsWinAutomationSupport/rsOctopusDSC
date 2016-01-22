function Get-TargetResource{
    [OutputType([Hashtable])]
    param (
        [ValidateSet("Present", "Absent")]
        [string]$Ensure = "Present",

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [ValidateSet("Started", "Stopped")]
        [string]$State = "Started",
        
        [string]$ApiKey,
        [string]$OctopusServerUrl,
        [string[]]$Environments,
        [string[]]$Roles,
        [string]$DefaultApplicationDirectory,
        [int]$ListenPort,
        [ValidateSet("named","detect","natted")]
        [string]$nicType="detect",
        [string]$nicName=$null
    )

    Write-Verbose "Checking if Tentacle is installed"
    $installLocation = (get-itemproperty -path "HKLM:\Software\Octopus\Tentacle" -ErrorAction SilentlyContinue).InstallLocation
    $present = (($installLocation -ne $null) -and (Test-Path "C:\Octopus\$($Name)\Tentacle.config"))
    Write-Verbose "Tentacle present: $present"
    
    $currentEnsure = if ($present) { "Present" } else { "Absent" }

    $serviceName = (Get-TentacleServiceName $Name)
    Write-Verbose "Checking for Windows Service: $serviceName"
    $serviceInstance = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    $currentState = "Stopped"
    if ($serviceInstance -ne $null) 
    {
        Write-Verbose "Windows service: $($serviceInstance.Status)"
        if ($serviceInstance.Status -eq "Running") 
        {
            $currentState = "Started"
        }
        
        if ($currentEnsure -eq "Absent") 
        {
            Write-Verbose "Since the Windows Service is still installed, the service is present"
            $currentEnsure = "Present"
        }
    } 
    else 
    {
        Write-Verbose "Windows service: Not installed"
        $currentEnsure = "Absent"
    }

    return @{
        Name = $Name; 
        Ensure = $currentEnsure;
        State = $currentState;
    };
}

function Set-TargetResource{
    param (       
        [ValidateSet("Present", "Absent")]
        [string]$Ensure = "Present",

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [ValidateSet("Started", "Stopped")]
        [string]$State = "Started",
        
        [string]$ApiKey,
        [string]$OctopusServerUrl,
        [string[]]$Environments,
        [string[]]$Roles,
        [string]$DefaultApplicationDirectory = "$($env:SystemDrive)\Applications",
        [int]$ListenPort = 10933,
        [ValidateSet("named","detect","natted")]
        [string]$nicType="detect",
        [string]$nicName=$null
   )

    if ($Ensure -eq "Absent" -and $State -eq "Started") 
    {
        throw "Invalid configuration: service cannot be both 'Absent' and 'Started'"
    }

    <#if ( (-not $InitialDeploy) -and ($DeployProject -or $DeployVersion))
    {
        throw "Invalid configuration: Resource set to not do initial deploy but Project and/or Version to deploy to specified"
    }#>

    $currentResource = (Get-TargetResource -Name $Name)

    Write-Verbose "Configuring Tentacle..."

    if ($State -eq "Stopped" -and $currentResource["State"] -eq "Started") 
    {
        $serviceName = (Get-TentacleServiceName $Name)
        Write-Verbose "Stopping $serviceName"
        Stop-Service -Name $serviceName -Force
    }

    if ($Ensure -eq "Absent" -and $currentResource["Ensure"] -eq "Present")
    {
        Remove-TentacleRegistration -name $Name -apiKey $ApiKey -octopusServerUrl $OctopusServerUrl
        
        $serviceName = (Get-TentacleServiceName $Name)
        Write-Verbose "Deleting service $serviceName..."
        Invoke-AndAssert { & sc.exe delete $serviceName }
        
        # Uninstall msi
        Write-Verbose "Uninstalling Tentacle..."
        $tentaclePath = "$($env:SystemDrive)\Octopus\Tentacle.msi"
        $msiLog = "$($env:SystemDrive)\Octopus\Tentacle.msi.uninstall.log"
        if (test-path $tentaclePath)
        {
            $msiExitCode = (Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $tentaclePath /quiet /l*v $msiLog" -Wait -Passthru).ExitCode
            Write-Verbose "Tentacle MSI installer returned exit code $msiExitCode"
            if ($msiExitCode -ne 0) 
            {
                throw "Removal of Tentacle failed, MSIEXEC exited with code: $msiExitCode. View the log at $msiLog"
            }
        }
        else 
        {
            throw "Tentacle cannot be removed, because the MSI could not be found."
        }
    } 
    elseif ($Ensure -eq "Present" -and $currentResource["Ensure"] -eq "Absent") 
    {
        Write-Verbose "Installing Tentacle..."
        New-Tentacle -name $Name -apiKey $ApiKey -octopusServerUrl $OctopusServerUrl -port $ListenPort -nicType $nicType -nicName $nicName -environments $Environments -roles $Roles -DefaultApplicationDirectory $DefaultApplicationDirectory
        Write-Verbose "Tentacle installed!"
    }

    if ($State -eq "Started" -and $currentResource["State"] -eq "Stopped") 
    {
        $serviceName = (Get-TentacleServiceName $Name)
        Write-Verbose "Starting $serviceName"
        Start-Service -Name $serviceName
    }

    Write-Verbose "Finished"
}

function Test-TargetResource{
    param (       
        [ValidateSet("Present", "Absent")]
        [string]$Ensure = "Present",

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [ValidateSet("Started", "Stopped")]
        [string]$State = "Started",
        
        [string]$ApiKey,
        [string]$OctopusServerUrl,
        [string[]]$Environments,
        [string[]]$Roles,
        [string]$DefaultApplicationDirectory,
        [int]$ListenPort,
        [ValidateSet("named","detect","natted")]
        [string]$nicType="detect",
        [string]$nicName=$null
    )
 
    $currentResource = (Get-TargetResource -Name $Name)

    $ensureMatch = $currentResource["Ensure"] -eq $Ensure
    Write-Verbose "Ensure: $($currentResource["Ensure"]) vs. $Ensure = $ensureMatch"
    if (!$ensureMatch) 
    {
        return $false
    }
    
    $stateMatch = $currentResource["State"] -eq $State
    Write-Verbose "State: $($currentResource["State"]) vs. $State = $stateMatch"
    if (!$stateMatch) 
    {
        return $false
    }

    return $true
}

function Get-TentacleServiceName{
    param ( [string]$instanceName )

    if ($instanceName -eq "Tentacle") 
    {
        return "OctopusDeploy Tentacle"
    } 
    else 
    {
        return "OctopusDeploy Tentacle: $instanceName"
    }
}

function Request-File{
    param (
        [string]$url,
        [string]$saveAs
    )
 
    Write-Verbose "Downloading $url to $saveAs"
    $downloader = new-object System.Net.WebClient
    $downloader.DownloadFile($url, $saveAs)
}

function Invoke-AndAssert{
    param ($block) 
  
    & $block | Write-Verbose
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) 
    {
        throw "Command returned exit code $LASTEXITCODE"
    }
}
 
# After the Tentacle is registered with Octopus, Tentacle listens on a TCP port, and Octopus connects to it. The Octopus server
# needs to know the public IP address to use to connect to this Tentacle instance. Is there a way in Windows Azure in which we can 
# know the public IP/host name of the current machine?
function VerifyConnection{
    param(
        $serverAddress,
        $port
    )

    Return Test-NetConnection $serverAddress -Port $port -InformationLevel Detailed -Verbose
}
function Get-RegistrationIP{
    param(
        $nicType,
        $nicName,
        $url
    )

    $urlRegex = "(http[s]?|[s]?ftp[s]?)(:\/\/)([^\s,]+)"; $port = $null; $ipAddress = $null
    if($url -match $urlRegex){
        $useHttps = ($url.Split("//") | select -First 1) -eq "https:"
        $serverAddress = $url.Split("//") | select -Last 1
    }
    else{$serverAddress = $url}
    if($serverAddress.Contains(":")){
        $port = $serverAddress.Split(":")[1]
        $serverAddress = $serverAddress.Split(":")[0]
    }
    if($useHttps -and ($port -eq $null)){$port = 443}
    elseif($port -eq $null){$port = 80}
    Write-Verbose "Connection tests will use address $($serverAddress) on port $($port)"

    switch($nicType){
        "named"{
            $netAdapter = Get-NetAdapter -InterfaceAlias $nicName -ErrorAction SilentlyContinue
            if(($netAdapter -eq $null) -or ($netAdapter.Status -ne "Up")){
                throw "Selected NIC $($nicName) does not exist or does not have a connection to the network."
            }
            $testResult = VerifyConnection $serverAddress $port
            if($testResult.TcpTestSucceeded -and ($testResult.InterfaceAlias -eq $netAdapter.Name)){
                $ipAddress = (Get-NetIPAddress -InterfaceAlias $netAdapter.Name -AddressFamily IPv4 -SkipAsSource $false -ErrorAction SilentlyContinue).IPv4Address
            }
        }
        "detect"{
            $testResult = VerifyConnection $serverAddress $port
            if($testResult.TcpTestSucceeded){
                $ipAddress = $testResult.SourceAddress.IPv4Address
            }
        }
        "natted"{
            $testResult = VerifyConnection $serverAddress $port
            if($testResult.TcpTestSucceeded){
                $downloader = new-object System.Net.WebClient
                $ipAddress = $downloader.DownloadString("http://icanhazip.com").Trim()
            }
        }
    }

    Return $ipAddress
}
<#function Get-MyPublicIPAddress([string]$RegisteredNic,[bool]$isNatted,[string]$OctopusServerUrl){
    
    $downloader = new-object System.Net.WebClient
    #First Verify the adapter exists
    $netAdapter = Get-NetAdapter -InterfaceAlias $RegisteredNic -ErrorAction SilentlyContinue
    if($netAdapter -eq $null -and $RegisteredNic -ne "AWSNIC"){
        throw "Selected NIC $($RegisteredNic) does not exist"
    }

    #If adapter is natted, find the actual Public IP
    if($isNatted){
        Write-Verbose "NIC $($RegisteredNic) is natted. Determining actual public IP"
        $ip = $downloader.DownloadString("http://icanhazip.com").Trim()
    }
    #If this is an AWS Server, using the AWSNIC as your interface name will direct this resource to scrape the machine's metadata for the local IP
    elseif($RegisteredNic -eq "AWSNIC"){
        Write-Verbose "Getting IP Address from AWS metadata."
        $ip = $downloader.DownloadString("http://169.254.169.254/latest/meta-data/local-ipv4").Trim()
        Write-Verbose "Metadata returned $($ip) as this machine's IP Address."
    }
    #Otherwise if you know the name of your network interface, this resource will get the IP of the interface that matches the interface name you provided.
    else{
        Write-Verbose "Getting IP address of $($RegisteredNic) NIC"
        $ip = Get-NetIPAddress -InterfaceAlias $RegisteredNic -AddressFamily IPv4 | select -exp IPAddress
    }

    #Test the connection to the Octopus Server. If it is not reachable, throw an error
    #$urlRegex = �([a-zA-Z]{3,})://([\w-]+\.)+[\w-]+(/[\w- ./?%&=]*)*?�
    $urlRegex = "(http[s]?|[s]?ftp[s]?)(:\/\/)([^\s,]+)"
    if($OctopusServerUrl -match $urlRegex){
        $OctopusServerUrl = $OctopusServerUrl.Split("//") | select -Last 1
    }
    if($OctopusServerUrl.Contains(":")){
        $port = $OctopusServerUrl.Split(":")[1]
        $OctopusServerUrl = $OctopusServerUrl.Split(":")[0]
        $adapterTest = Test-NetConnection $OctopusServerUrl -port $port -InformationLevel Detailed
        $testResult = $adapterTest.TcpTestSucceeded
    }
    else{
        $adapterTest = Test-NetConnection $OctopusServerUrl HTTP -InformationLevel Detailed
        $testResult = $adapterTest.TcpTestSucceeded
    }
    Write-Verbose "The connection test to $($OctopusServerUrl) from $($ip) using the $($RegisteredNic) interface returned: $($testResult)."
    if(!($testResult -and (($adapterTest.InterfaceAlias -eq $RegisteredNic) -or $RegisteredNic -eq "AWSNIC"))){
        throw "Cannot reach Octopus Server $($OctopusServerUrl) from Network $($RegisteredNic). Please check your connection and try running your configuration again"
    }
    else{return $ip}
}#>
 
function New-Tentacle{
    param (
        [Parameter(Mandatory=$True)]
        [string]$name,
        [Parameter(Mandatory=$True)]
        [string]$apiKey,
        [Parameter(Mandatory=$True)]
        [string]$octopusServerUrl,
        [Parameter(Mandatory=$True)]
        [string[]]$environments,
        [Parameter(Mandatory=$True)]
        [string[]]$roles,
        [int] $port,
        [ValidateSet("named","detect","natted")]
        $nicType="detect",
        $nicName=$null,
        #[string]$RegisteredNic,
        #[bool]$isNatted=$false,
        [string]$DefaultApplicationDirectory
    )
 
    if ($port -eq 0){
        $port = 10933
    }

    Write-Verbose "Beginning Tentacle installation" 
 
    Write-Verbose "Open port $port on Windows Firewall"
    Invoke-AndAssert { & netsh.exe advfirewall firewall add rule protocol=TCP dir=in localport=$port action=allow name="Octopus Tentacle: $Name" }
    
    #$ipAddress = Get-MyPublicIPAddress -RegisteredNic $RegisteredNic -isNatted $isNatted -OctopusServerUrl $octopusServerUrl
    $ipAddress = Get-RegistrationIP -nicType $nicType -nicName $nicName -url $octopusServerUrl    
    if($ipAddress -eq $null){
        throw "I don't have an IP Address to register with"
    }
 
    Write-Verbose "Public IP address: $($ipAddress)"
    Write-Verbose "Configuring and registering Tentacle"
  
    pushd "${env:ProgramFiles}\Octopus Deploy\Tentacle"
 
    $tentacleHomeDirectory = "$($env:SystemDrive)\Octopus"
    $tentacleAppDirectory = $DefaultApplicationDirectory
    $tentacleConfigFile = "$($env:SystemDrive)\Octopus\$Name\Tentacle.config"
    Invoke-AndAssert { & .\tentacle.exe create-instance --instance $name --config $tentacleConfigFile --console }
    Invoke-AndAssert { & .\tentacle.exe configure --instance $name --home $tentacleHomeDirectory --console }
    Invoke-AndAssert { & .\tentacle.exe configure --instance $name --app $tentacleAppDirectory --console }
    Invoke-AndAssert { & .\tentacle.exe configure --instance $name --port $port --console }
    Invoke-AndAssert { & .\tentacle.exe new-certificate --instance $name --console }
    Invoke-AndAssert { & .\tentacle.exe service --install --instance $name --console }

    $registerArguments = @("register-with", "--instance", $name, "--server", $octopusServerUrl, "--name", $env:COMPUTERNAME, "--publicHostName", $ipAddress, "--apiKey", $apiKey, "--comms-style", "TentaclePassive", "--force", "--console")

    foreach ($environment in $environments){
        foreach ($e2 in $environment.Split(',')){
            $registerArguments += "--environment"
            $registerArguments += $e2.Trim()
        }
    }
    foreach ($role in $roles){
        foreach ($r2 in $role.Split(',')){
            $registerArguments += "--role"
            $registerArguments += $r2.Trim()
        }
    }

    Write-Verbose "Registering with arguments: $registerArguments"
    Invoke-AndAssert { & .\tentacle.exe ($registerArguments) }

    popd
    Write-Verbose "Tentacle commands complete"
}


function Remove-TentacleRegistration{
    param (
        [Parameter(Mandatory=$True)]
        [string]$name,
        [Parameter(Mandatory=$True)]
        [string]$apiKey,
        [Parameter(Mandatory=$True)]
        [string]$octopusServerUrl
    )
  
    $tentacleDir = "${env:ProgramFiles}\Octopus Deploy\Tentacle"
    if ((test-path $tentacleDir) -and (test-path "$tentacleDir\tentacle.exe")){
        Write-Verbose "Beginning Tentacle deregistration" 
        Write-Verbose "Tentacle commands complete"
        pushd $tentacleDir
        Invoke-AndAssert { & .\tentacle.exe deregister-from --instance "$name" --server $octopusServerUrl --apiKey $apiKey --console }
        popd
    }
    else{
        Write-Verbose "Could not find Tentacle.exe"
    }
}