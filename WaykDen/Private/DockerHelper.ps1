
class DockerHealthcheck
{
    [string] $Test
    [string] $Interval
    [string] $Timeout
    [string] $Retries
    [string] $StartPeriod

    DockerHealthcheck() { }

    DockerHealthcheck([string] $Test) {
        $this.Test = $Test
        $this.Interval = "5s"
        $this.Timeout = "2s"
        $this.Retries = "5"
        $this.StartPeriod = "1s"
    }

    DockerHealthcheck([DockerHealthcheck] $other) {
        $this.Test = $other.Test
        $this.Interval = $other.Interval
        $this.Timeout = $other.Timeout
        $this.Retries = $other.Retries
        $this.StartPeriod = $other.StartPeriod
    }
}

class DockerLogging
{
    [string] $Driver
    [Hashtable] $Options

    DockerLogging() { }

    DockerLogging([string] $SyslogAddress) {
        $this.Driver = "syslog"
        $this.Options = [ordered]@{
            'syslog-format' = 'rfc5424'
            'syslog-facility' = 'daemon'
            'syslog-address' = $SyslogAddress
        }
    }

    DockerLogging([DockerLogging] $other) {
        $this.Driver = $other.Driver

        if ($other.Options) {
            $this.Options = $other.Options.Clone()
        }
    }
}

class DockerService
{
    [string] $Image
    [string] $Platform
    [string] $ContainerName
    [bool] $External
    [string[]] $DependsOn
    [string[]] $Networks
    [Hashtable] $Environment
    [string[]] $Volumes
    [string] $Command
    [string[]] $Ports
    [DockerHealthcheck] $Healthcheck
    [DockerLogging] $Logging

    DockerService() { }

    DockerService([DockerService] $other) {
        $this.Image = $other.Image
        $this.Platform = $other.Platform
        $this.ContainerName = $other.ContainerName

        $this.External = $other.External

        if ($other.DependsOn) {
            $this.DependsOn = $other.DependsOn.Clone()
        }

        if ($other.Networks) {
            $this.Networks = $other.Networks.Clone()
        }

        if ($other.Environment) {
            $this.Environment = $other.Environment.Clone()
        }

        if ($other.Volumes) {
            $this.Volumes = $other.Volumes.Clone()
        }
    
        $this.Command = $other.Command

        if ($other.Ports) {
            $this.Ports = $other.Ports.Clone()
        }

        if ($other.Healthcheck) {
            $this.Healthcheck = [DockerHealthcheck]::new($other.Healthcheck)
        }
     
        if ($other.Logging)  {
            $this.Logging = [DockerLogging]::new($other.Logging)
        }
    }
}

function Get-ContainerExists
{
    param(
        [string] $Name
    )

    $exists = $(docker ps -aqf "name=$Name")
    return ![string]::IsNullOrEmpty($exists)
}

function Get-ContainerIsRunning
{
    param(
        [string] $Name
    )

    $running = $(docker inspect -f '{{.State.Running}}' $Name)
    return $running -Match 'true'
}

function Get-ContainerIsHealthy
{
    param(
        [string] $Name
    )

    $healthy = $(docker inspect -f '{{.State.Health.Status}}' $Name)
    return $healthy -Match 'healthy'
}

function Wait-ContainerHealthy
{
    param(
        [Parameter(Mandatory=$true)]
        [string] $Name
    )

    $seconds = 0
    $timeout = 15
    $interval = 1

    while (($seconds -lt $timeout) -And !(Get-ContainerIsHealthy -Name:$Name) -And (Get-ContainerIsRunning -Name:$Name)) {
        Start-Sleep -Seconds $interval
        $seconds += $interval
    }

    return (Get-ContainerIsHealthy -Name:$Name)
}

function Stop-Container
{
    param(
        [Parameter(Mandatory=$true)]
        [string] $Name,
        [switch] $Quiet
    )

    $args = @('docker', 'stop')

    $args += $Name
    $cmd = $args -Join " "

    if (-Not $Quiet) {
        Write-Host $cmd
    }

    Invoke-Expression $cmd | Out-Null
}

function Remove-Container
{
    param(
        [Parameter(Mandatory=$true)]
        [string] $Name,
        [switch] $Quiet,
        [switch] $Force
    )

    $args = @('docker', 'rm')

    if ($Force) {
        $args += '-f'
    }

    $args += $Name
    $cmd = $args -Join " "

    if (-Not $Quiet) {
        Write-Host $cmd
    }

    Invoke-Expression $cmd | Out-Null
}

function Get-DockerNetworkExists
{
    param(
        [Parameter(Mandatory=$true)]
        [string] $Name
    )

    $exists = $(docker network ls -qf "name=$Name")
    return ![string]::IsNullOrEmpty($exists)
}

function New-DockerNetwork
{
    param(
        [Parameter(Mandatory=$true)]
        [string] $Name,
        [string] $Platform,
        [switch] $Force
    )

    if (!(Get-DockerNetworkExists -Name:$Name)) {
        $cmd = @('network', 'create')
        
        if ($Platform -eq 'windows') {
            $cmd += @('-d', 'nat')
        }

        $cmd += $Name # network name
        $Id = docker $cmd
    }
}

function New-DockerVolume
{
    param(
        [Parameter(Mandatory=$true)]
        [string] $Name,
        [switch] $Force
    )

    $output = $(docker volume ls -qf "name=$Name")

    if ([string]::IsNullOrEmpty($output)) {
        docker volume create $Name | Out-Null
    }
}

function Request-ContainerImage()
{
    param(
        [Parameter(Mandatory=$true)]
        [string] $Name,
        [switch] $Quiet
    )

    $args = @('docker', 'pull')

    if ($Quiet) {
        $args += '-q'
    }

    $args += $Name
    $cmd = $args -Join " "

    if (-Not $Quiet) {
        Write-Host $cmd
    }

    Invoke-Expression $cmd | Out-Null
}
