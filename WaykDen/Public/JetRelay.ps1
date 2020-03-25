
. "$PSScriptRoot/../Private/CertificateHelper.ps1"
. "$PSScriptRoot/../Private/PlatformHelper.ps1"
. "$PSScriptRoot/../Private/DockerHelper.ps1"
. "$PSScriptRoot/../Private/CaseHelper.ps1"
. "$PSScriptRoot/../Private/YamlHelper.ps1"

function Get-JetImage
{
    param(
        [string] $Platform
    )

    $image = if ($Platform -ne "windows") {
        "devolutions/devolutions-jet:0.10.0-buster"
    } else {
        "devolutions/devolutions-jet:0.10.0-servercore-ltsc2019"
    }

    return $image
}

class JetConfig
{
    [string] $JetInstance
    [string[]] $JetListeners

    [string] $DockerPlatform
    [string] $DockerImage
}

function Set-JetConfig
{
    [CmdletBinding()]
    param(
        [string] $ConfigPath,
        [string] $JetInstance,
        [string[]] $JetListeners,
        [string] $DockerPlatform,
        [string] $DockerImage,
        [string] $Force
    )

    $ConfigPath = Find-JetConfig -ConfigPath:$ConfigPath

    if (-Not (Test-Path -Path $ConfigPath -PathType 'Container')) {
        New-Item -Path $ConfigPath -ItemType 'Directory'
    }

    $ConfigFile = Join-Path $ConfigPath "jet-relay.yml"

    if (-Not (Test-Path -Path $ConfigFile -PathType 'Leaf')) {
        $config = [JetConfig]::new()
    } else {
        $config = Get-JetConfig -ConfigPath:$ConfigPath
    }

    $properties = [JetConfig].GetProperties() | ForEach-Object { $_.Name }
    foreach ($param in $PSBoundParameters.GetEnumerator()) {
        if ($properties -Contains $param.Key) {
            $config.($param.Key) = $param.Value
        }
    }

    ConvertTo-Yaml -Data $config -OutFile "$ConfigFile-2" -Force
 
    # always force overwriting jet-relay.yml when updating the config file
    ConvertTo-Yaml -Data (ConvertTo-SnakeCaseObject -Object $config) -OutFile $ConfigFile -Force
}

function Get-JetConfig
{
    [CmdletBinding()]
    [OutputType('JetConfig')]
    param(
        [string] $ConfigPath,
        [switch] $Expand
    )

    $ConfigPath = Find-JetConfig -ConfigPath:$ConfigPath

    $ConfigFile = Join-Path $ConfigPath "jet-relay.yml"
    $ConfigData = Get-Content -Path $ConfigFile -Raw -ErrorAction Stop
    $yaml = ConvertFrom-Yaml -Yaml $ConfigData -UseMergingParser -AllDocuments -Ordered

    $config = [JetConfig]::new()

    [JetConfig].GetProperties() | ForEach-Object {
        $Name = $_.Name
        $snake_name = ConvertTo-SnakeCase -Value $Name
        if ($yaml.Contains($snake_name)) {
            if ($yaml.$snake_name -is [string]) {
                if (![string]::IsNullOrEmpty($yaml.$snake_name)) {
                    $config.$Name = ($yaml.$snake_name).Trim()
                }
            } else {
                $config.$Name = $yaml.$snake_name
            }
        }
    }

    if ($Expand) {
        Expand-JetConfig $config
    }

    return $config
}

function Expand-JetConfig
{
    param(
        [JetConfig] $Config
    )

    if (-Not $config.DockerPlatform) {
        if (Get-IsWindows) {
            $config.DockerPlatform = "windows"
        } else {
            $config.DockerPlatform = "linux"
        }
    }

    if (-Not $config.DockerImage) {
        $config.DockerImage = Get-JetImage -Platform $config.DockerPlatform
    }

    if (-Not $config.JetListeners) {
        $config.JetListeners = @("tcp://0.0.0.0:8080")
    }
}

function Find-JetConfig
{
    param(
        [string] $ConfigPath
    )

    if (-Not $ConfigPath) {
        $ConfigPath = Get-Location
    }

    return $ConfigPath
}

function Import-JetCertificate
{
    [CmdletBinding()]
    param(
        [string] $ConfigPath,
        [string] $CertificateFile,
        [string] $PrivateKeyFile,
        [string] $Password
    )

    $ConfigPath = Find-JetConfig -ConfigPath:$ConfigPath
    $config = Get-JetConfig -ConfigPath:$ConfigPath

    $result = Get-PemCertificate -CertificateFile:$CertificateFile `
        -PrivateKeyFile:$PrivateKeyFile -Password:$Password
        
    $CertificateData = $result.Certificate
    $PrivateKeyData = $result.PrivateKey

    $JetRelayPath = Join-Path $ConfigPath "jet-relay"
    New-Item -Path $JetRelayPath -ItemType "Directory" -Force | Out-Null

    $JetRelayPemFile = Join-Path $JetRelayPath "jet-relay.pem"
    $JetRelayKeyFile = Join-Path $JetRelayPath "jet-relay.key"

    Set-Content -Path $JetRelayPemFile -Value $CertificateData -Force
    Set-Content -Path $JetRelayKeyFile -Value $PrivateKeyData -Force
}

function Get-JetService
{
    param(
        [string] $ConfigPath,
        [JetConfig] $Config
    )

    if ($config.DockerPlatform -eq "linux") {
        $PathSeparator = "/"
        $JetRelayDataPath = "/etc/jet-relay"
    } else {
        $PathSeparator = "\"
        $JetRelayDataPath = "c:\jet-relay"
    }

    $Service = [DockerService]::new()
    $Service.ContainerName = 'devolutions-jet'
    $Service.Image = $config.DockerImage
    $Service.Platform = $config.DockerPlatform
    $Service.TargetPorts = @(10256)

    foreach ($JetListener in $config.JetListeners) {
        $ListenerUrl = ([string[]] $($JetListener -Split ','))[0]
        $url = [System.Uri]::new($ListenerUrl)
        $Service.TargetPorts += @($url.Port)
    }

    $Service.PublishAll = $true
    $Service.Environment = [ordered]@{
        "JET_INSTANCE" = $config.JetInstance;
        "JET_UNRESTRICTED" = "true";
        "RUST_LOG" = "info";
    }
    $Service.Volumes = @("$ConfigPath/jet-relay:$JetRelayDataPath")
    $Service.External = $false

    if (Test-Path "$ConfigPath/jet-relay/jet-relay.pem" -PathType 'Leaf') {
        $Service.Environment['JET_CERTIFICATE_FILE'] = @($JetRelayDataPath, 'jet-relay.pem') -Join $PathSeparator
    }

    if (Test-Path "$ConfigPath/jet-relay/jet-relay.key" -PathType 'Leaf') {
        $Service.Environment['JET_PRIVATE_KEY_FILE'] = @($JetRelayDataPath, 'jet-relay.key') -Join $PathSeparator
    }

    $args = @()
    foreach ($JetListener in $config.JetListeners) {
        $args += @('-l', "`"$JetListener`"")
    }

    $Service.Command = $($args -Join " ")

    return $Service
}

function Start-JetRelay
{
    [CmdletBinding()]
    param(
        [string] $ConfigPath,
        [switch] $SkipPull
    )

    $ConfigPath = Find-JetConfig -ConfigPath:$ConfigPath
    $config = Get-JetConfig -ConfigPath:$ConfigPath
    Expand-JetConfig -Config $config

    $Service = Get-JetService -ConfigPath:$ConfigPath -Config:$config

    if (-Not $SkipPull) {
        # pull docker image
        Request-ContainerImage -Name $Service.Image
    }

    Start-DockerService -Service $Service -Remove
}

function Stop-JetRelay
{
    [CmdletBinding()]
    param(
        [string] $ConfigPath,
        [switch] $Remove
    )

    $ConfigPath = Find-JetConfig -ConfigPath:$ConfigPath
    $config = Get-JetConfig -ConfigPath:$ConfigPath
    Expand-JetConfig -Config $config

    $Service = Get-JetService -ConfigPath:$ConfigPath -Config:$config

    Write-Host "Stopping $($Service.ContainerName)"
    Stop-Container -Name $Service.ContainerName -Quiet

    if ($Remove) {
        Remove-Container -Name $Service.ContainerName
    }
}

function Restart-JetRelay
{
    [CmdletBinding()]
    param(
        [string] $ConfigPath
    )

    $ConfigPath = Find-JetConfig -ConfigPath:$ConfigPath
    Stop-JetRelay -ConfigPath:$ConfigPath
    Start-JetRelay -ConfigPath:$ConfigPath
}

Export-ModuleMember -Function `
    Set-JetConfig, Get-JetConfig, Import-JetCertificate, `
    Start-JetRelay, Stop-JetRelay, Restart-JetRelay
