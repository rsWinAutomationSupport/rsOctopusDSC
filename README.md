This repository contains a PowerShell module with a DSC resource that can be used to install the [Octopus Deploy](http://octopusdeploy.com) Tentacle agent.

## Install Tentacle Package
Installation of the MSI Package has been extracted from this resource, make use of the Package resource to install as demonstrated below

```
File OctopusPath{
	Ensure = "Present"
	Type = "Directory"
	DestinationPath = "C:\Octopus"
}
Package OctoTentacle{
	Name = "Octopus Deploy Tentacle"
	Ensure = "Present"
	Path = "https://download.octopusdeploy.com/octopus/Octopus.Tentacle.2.6.5.1010-x64.msi"
	Arguments = "/l*v $($env:SystemDrive)\Octopus\Tentacle.msi.log"
	ProductId = ""
	DependsOn = @("[File]OctopusPath")
}
```

## Sample

First, ensure the OctopusDSC module is on your `$env:PSModulePath`. Then you can create and apply configuration like this.

```
Configuration SampleConfig
{
    param ($ApiKey, $OctopusServerUrl, $Environments, $Roles, $ListenPort)
 
    Import-DscResource -Module OctopusDSC
 
    Node "localhost"
    {
        cTentacleAgent OctopusTentacle{ 
            Ensure = "Present" 
            State = "Started"

            # Tentacle instance name. Leave it as 'Tentacle' unless you have more 
            # than one instance
            Name = "Tentacle"

            # Registration - all parameters required
            ApiKey = "API-ABCDEF12345678910"
            OctopusServerUrl = "https://demo.octopusdeploy.com" #Please ensure there is no trailing forward slash in the URL
            Environments = "Staging"
            Roles = @("web-server", "app-server")

            # Optional settings
            ListenPort = 10933
            nicType = "detect" #This sets the value for what kind of NIC we should expect. "detect" will test the connection to the octopus server and use the NIC that successfully connects, it is the default value. "named" is where you know the name of the NIC and the connection will be tested and verify the NIC named is the one that reached the octopus server. "nicName" variable is required if this is set. "natted" will verify a connection to the octopus server and then it will call a 3rd party service to determine it's public IP
			nicName #This is only required if nicType is set to "named"
            DefaultApplicationDirectory = "C:\Octopus"
        }
    }
}
 
SampleConfig -ApiKey "API-ABCDEF12345678910" -OctopusServerUrl "https://demo.octopusdeploy.com/" -Environments @("Development") -Roles @("web-server", "app-server") -ListenPort 10933

Start-DscConfiguration .\SampleConfig -Verbose -wait

Test-DscConfiguration
```

## Deploying Projects
```
Configuration SampleConfig
{
    param ($ApiKey, $OctopusServerUrl, $DeployProject, $DeployVersion, $Environments, $Roles, $ListenPort)
 
    Import-DscResource -Module OctopusDSC
 
    Node "localhost"
	{
		cProjectDeploy Config{
            ApiKey = "API-ABCDEF12345678910"
            OctopusServerUrl = "https://demo.octopusdeploy.com/"
            DeployProject = "Sample Project"
            Environments = "Staging"
            DeployVersion = "1.1.0.121"
        }
	}
}

SampleConfig -ApiKey "API-ABCDEF12345678910" -OctopusServerUrl "https://demo.octopusdeploy.com/" -DeployProject "DotNet Project" -DeployVersion "1.0.3" -Environments @("Development") -Roles @("web-server", "app-server") -ListenPort 10933

Start-DscConfiguration .\SampleConfig -Verbose -wait

Test-DscConfiguration
```

Repeat this config block as many times as necessary to deploy all projects.

## Settings

When `Ensure` is set to `Present`, the resource will:

 1. Download the Tentacle MSI from the internet
 2. Install the MSI
 3. Configure Tentacle in listening mode on the specified port (10933 by default)
 4. Add a Windows firewall exception for the listening port
 5. Register the Tentacle with your Octopus server, using the registration settings

When `Ensure` is set to `Absent`, the resource will:

 1. De-register the Tentacle from your Octopus server, using the registration settings
 2. Delete the Tentacle windows service
 3. Uninstall using the MSI

When `State` is `Started`, the resource will ensure that the Tentacle windows service is running. When `Stopped`, it will ensure the service is stopped.

## Drift

Currently the resource only considers the `Ensure` and `State` properties when testing for drift. 

This means that if you set `Ensure` to `Present` to install Tentacle, then later set it to `Absent`, testing the configuration will return `$false`. Likewise if you set the `State` to `Stopped` and the service is running. 

However, if you were to set the `ListenPort` to a new port, the drift detection isn't smart enough to check the old configuration, nor update the registered machine. You'll need to uninstall and reinstall for these other settings to take effect.

## Development
If you are making changes to the module, keep in mind that your changes may not be loaded, as the module gets cached by `WmiPrvSE`. You can use the following command to kill `WmiPrvSE`:

```
Stop-Process -Name WmiPrvSE -Force -ErrorAction SilentlyContinue | out-null
```

