
. "$PSScriptRoot/../Private/CaseHelper.ps1"
. "$PSScriptRoot/../Private/YamlHelper.ps1"
. "$PSScriptRoot/../Private/TraefikHelper.ps1"
. "$PSScriptRoot/../Private/RandomGenerator.ps1"
. "$PSScriptRoot/../Private/CertificateHelper.ps1"

class WaykDenConfig
{
    # DenServer
    [string] $Realm
    [string] $ExternalUrl
    [string] $ListenerUrl
    [string] $ServerMode
    [int] $ServerCount
    [string] $DenServerUrl
    [string] $DenRouterUrl
    [string] $DenApiKey
    [bool] $ServerExternal

    # MongoDB
    [string] $MongoUrl
    [string] $MongoVolume
    [bool] $MongoExternal

    # Jet
    [string] $JetRelayUrl
    [string] $JetServerUrl

    # LDAP
    [string] $LdapServerUrl
    [string] $LdapServerIp
    [string] $LdapUsername
    [string] $LdapPassword
    [string] $LdapUserGroup
    [string] $LdapServerType
    [string] $LdapBaseDn
    [string] $LdapBindType
    [bool] $LdapCertificateValidation

    # Picky
    [string] $PickyUrl
    [string] $PickyApiKey
    [bool] $PickyExternal

    # Lucid
    [string] $LucidUrl
    [string] $LucidApiKey
    [string] $LucidAdminUsername
    [string] $LucidAdminSecret
    [bool] $LucidExternal

    # NATS
    [string] $NatsUrl
    [string] $NatsUsername
    [string] $NatsPassword
    [bool] $NatsExternal
    
    # Redis
    [string] $RedisUrl
    [string] $RedisPassword
    [bool] $RedisExternal

    # Docker
    [string] $DockerNetwork
    [string] $DockerPlatform
    [string] $DockerIsolation
    [string] $DockerHost
    [string] $SyslogServer
}

function Find-WaykDenConfig
{
    param(
        [string] $ConfigPath
    )

    if (-Not $ConfigPath) {
        $ConfigPath = Get-Location
    }

    if ($Env:DEN_CONFIG_PATH) {
        $ConfigPath = $Env:DEN_CONFIG_PATH
    }

    return $ConfigPath
}

function Set-WaykDenConfigPath
{
    param(
        [Parameter(Mandatory=$true,Position=0)]
        [string] $ConfigPath
    )

    $Env:DEN_CONFIG_PATH = $ConfigPath
}

function Get-WaykDenPath()
{
	[CmdletBinding()]
	param(
		[Parameter(Mandatory,Position=0)]
        [ValidateSet("ConfigPath","GlobalPath","LocalPath")]
		[string] $PathType
	)

    $DisplayName = "Wayk Den"
    $LowerName = "wayk-den"
    $CompanyName = "Devolutions"
	$HomePath = Resolve-Path '~'

	if (Get-IsWindows)	{
		$LocalPath = $Env:AppData + "\${CompanyName}\${DisplayName}";
		$GlobalPath = $Env:ProgramData + "\${CompanyName}\${DisplayName}"
	} elseif ($IsMacOS) {
		$LocalPath = "$HomePath/Library/Application Support/${DisplayName}"
		$GlobalPath = "/Library/Application Support/${DisplayName}"
	} elseif ($IsLinux) {
		$LocalPath = "$HomePath/.config/${LowerName}"
		$GlobalPath = "/etc/${LowerName}"
	}

	switch ($PathType) {
		'LocalPath' { $LocalPath }
		'GlobalPath' { $GlobalPath }
        'ConfigPath' { $GlobalPath }
		default { throw("Invalid path type: $PathType") }
	}
}

function Expand-WaykDenConfigKeys
{
    param(
        [WaykDenConfig] $Config
    )

    if (-Not $config.DenApiKey) {
        $config.DenApiKey = New-RandomString -Length 32
    }

    if (-Not $config.PickyApiKey) {
        $config.PickyApiKey = New-RandomString -Length 32
    }

    if (-Not $config.LucidApiKey) {
        $config.LucidApiKey = New-RandomString -Length 32
    }

    if (-Not $config.LucidAdminUsername) {
        $config.LucidAdminUsername = New-RandomString -Length 16
    }

    if (-Not $config.LucidAdminSecret) {
        $config.LucidAdminSecret = New-RandomString -Length 10
    }
}

function Expand-WaykDenConfig
{
    param(
        [WaykDenConfig] $Config
    )

    $DockerNetworkDefault = "den-network"
    $MongoUrlDefault = "mongodb://den-mongo:27017"
    $MongoVolumeDefault = "den-mongodata"
    $ServerModeDefault = "Private"
    $ListenerUrlDefault = "http://0.0.0.0:4000"
    $JetServerUrlDefault = "api.jet-relay.net:8080"
    $JetRelayUrlDefault = "https://api.jet-relay.net"
    $PickyUrlDefault = "http://den-picky:12345"
    $LucidUrlDefault = "http://den-lucid:4242"
    $DenServerUrlDefault = "http://den-server:10255"
    $DenRouterUrlDefault = "http://den-server:4491"

    if (-Not $config.DockerNetwork) {
        $config.DockerNetwork = $DockerNetworkDefault
    }

    if (($config.DockerNetwork -Match "none") -and $config.DockerHost) {
        $MongoUrlDefault = $MongoUrlDefault -Replace "den-mongo", $config.DockerHost
        $PickyUrlDefault = $PickyUrlDefault -Replace "den-picky", $config.DockerHost
        $LucidUrlDefault = $LucidUrlDefault -Replace "den-lucid", $config.DockerHost
        $DenServerUrlDefault = $DenServerUrlDefault -Replace "den-server", $config.DockerHost
        $DenRouterUrlDefault = $DenRouterUrlDefault -Replace "den-server", $config.DockerHost
    }

    if (-Not $config.DockerPlatform) {
        if (Get-IsWindows) {
            $config.DockerPlatform = "windows"
        } else {
            $config.DockerPlatform = "linux"
        }
    }

    if (-Not $config.ServerMode) {
        $config.ServerMode = $ServerModeDefault
    }

    if (-Not $config.ServerCount) {
        $config.ServerCount = 1
    }

    if (-Not $config.ListenerUrl) {
        $config.ListenerUrl = $ListenerUrlDefault
    }

    if (-Not $config.MongoUrl) {
        $config.MongoUrl = $MongoUrlDefault
    }

    if (-Not $config.MongoVolume) {
        $config.MongoVolume = $MongoVolumeDefault
    }

    if (-Not $config.JetServerUrl) {
        $config.JetServerUrl = $JetServerUrlDefault
    }

    if (-Not $config.JetRelayUrl) {
        $config.JetRelayUrl = $JetRelayUrlDefault
    }

    if (-Not $config.PickyUrl) {
        $config.PickyUrl = $PickyUrlDefault
    }

    if (-Not $config.LucidUrl) {
        $config.LucidUrl = $LucidUrlDefault
    }

    if (-Not $config.DenServerUrl) {
        $config.DenServerUrl = $DenServerUrlDefault
    }

    if (-Not $config.DenRouterUrl) {
        $config.DenRouterUrl = $DenRouterUrlDefault
    }
}

function Export-TraefikToml()
{
    param(
        [string] $ConfigPath
    )

    $ConfigPath = Find-WaykDenConfig -ConfigPath:$ConfigPath

    $config = Get-WaykDenConfig -ConfigPath:$ConfigPath
    Expand-WaykDenConfig $config

    $TraefikPath = Join-Path $ConfigPath "traefik"
    New-Item -Path $TraefikPath -ItemType "Directory" -Force | Out-Null

    $TraefikTomlFile = Join-Path $TraefikPath "traefik.toml"

    $TraefikToml = New-TraefikToml -Platform $config.DockerPlatform `
        -ListenerUrl $config.ListenerUrl `
        -LucidUrl $config.LucidUrl `
        -PickyUrl $config.PickyUrl `
        -DenRouterUrl $config.DenRouterUrl `
        -DenServerUrl $config.DenServerUrl

    Set-Content -Path $TraefikTomlFile -Value $TraefikToml
}

function Export-HostInfo()
{
    param(
        [string] $ConfigPath,
        [PSCustomObject] $HostInfo
    )

    $ConfigPath = Find-WaykDenConfig -ConfigPath:$ConfigPath

    $config = Get-WaykDenConfig -ConfigPath:$ConfigPath
    Expand-WaykDenConfig $config

    $DenServerPath = Join-Path $ConfigPath "den-server"
    New-Item -Path $DenServerPath -ItemType "Directory" -Force | Out-Null

    $JsonValue = $($HostInfo | ConvertTo-Json)
    $HostInfoFile = Join-Path $DenServerPath "host_info.json"
    Set-Content -Path $HostInfoFile -Value $JsonValue -Force
}

function New-WaykDenConfig
{
    [CmdletBinding()]
    param(
        [string] $ConfigPath,
    
        # Server
        [Parameter(Mandatory=$true)]
        [string] $Realm,
        [Parameter(Mandatory=$true)]
        [string] $ExternalUrl,
        [string] $ListenerUrl,
        [string] $ServerMode,
        [int] $ServerCount,
        [string] $DenServerUrl,
        [string] $DenRouterUrl,
        [string] $DenApiKey,
        [bool] $ServerExternal,

        # MongoDB
        [string] $MongoUrl,
        [string] $MongoVolume,
        [bool] $MongoExternal,

        # Jet
        [string] $JetRelayUrl,

        # LDAP
        [string] $LdapServerUrl,
        [string] $LdapServerIp,
        [string] $LdapUsername,
        [string] $LdapPassword,
        [string] $LdapUserGroup,
        [string] $LdapServerType,
        [string] $LdapBaseDn,
        [string] $LdapBindType,
        [bool] $LdapCertificateValidation,

        # Picky
        [string] $PickyUrl,
        [string] $PickyApiKey,
        [bool] $PickyExternal,

        # Lucid
        [string] $LucidUrl,
        [string] $LucidApiKey,
        [string] $LucidAdminUsername,
        [string] $LucidAdminSecret,
        [bool] $LucidExternal,

        # NATS
        [string] $NatsUrl,
        [string] $NatsUsername,
        [string] $NatsPassword,
        [bool] $NatsExternal,
        
        # Redis
        [string] $RedisUrl,
        [string] $RedisPassword,
        [bool] $RedisExternal,

        # Docker
        [string] $DockerNetwork,
        [string] $DockerPlatform,
        [string] $DockerIsolation,
        [string] $DockerHost,
        [string] $SyslogServer,

        [switch] $Force
    )

    $ConfigPath = Find-WaykDenConfig -ConfigPath:$ConfigPath

    New-Item -Path $ConfigPath -ItemType "Directory" -Force | Out-Null
    $ConfigFile = Join-Path $ConfigPath "wayk-den.yml"

    $DenServerPath = Join-Path $ConfigPath "den-server"
    $DenPublicKeyFile = Join-Path $DenServerPath "den-public.pem"
    $DenPrivateKeyFile = Join-Path $DenServerPath "den-private.key"
    New-Item -Path $DenServerPath -ItemType "Directory" -Force | Out-Null

    if (!((Test-Path -Path $DenPublicKeyFile -PathType "Leaf") -and
          (Test-Path -Path $DenPrivateKeyFile -PathType "Leaf"))) {
            $KeyPair = New-RsaKeyPair -KeySize 2048
            Set-Content -Path $DenPublicKeyFile -Value $KeyPair.PublicKey -Force
            Set-Content -Path $DenPrivateKeyFile -Value $KeyPair.PrivateKey -Force
    }

    $config = [WaykDenConfig]::new()
    
    $properties = [WaykDenConfig].GetProperties() | ForEach-Object { $_.Name }
    foreach ($param in $PSBoundParameters.GetEnumerator()) {
        if ($properties -Contains $param.Key) {
            $config.($param.Key) = $param.Value
        }
    }

    Expand-WaykDenConfigKeys -Config:$config

    ConvertTo-Yaml -Data (ConvertTo-SnakeCaseObject -Object $config) -OutFile $ConfigFile -Force:$Force

    Export-TraefikToml -ConfigPath:$ConfigPath
}

function Set-WaykDenConfig
{
    [CmdletBinding()]
    param(
        [string] $ConfigPath,
    
        # Server
        [string] $Realm,
        [string] $ExternalUrl,
        [string] $ListenerUrl,
        [string] $ServerMode,
        [int] $ServerCount,
        [string] $DenServerUrl,
        [string] $DenRouterUrl,
        [string] $DenApiKey,
        [bool] $ServerExternal,

        # MongoDB
        [string] $MongoUrl,
        [string] $MongoVolume,
        [bool] $MongoExternal,

        # Jet
        [string] $JetRelayUrl,

        # LDAP
        [string] $LdapServerUrl,
        [string] $LdapServerIp,
        [string] $LdapUsername,
        [string] $LdapPassword,
        [string] $LdapUserGroup,
        [string] $LdapServerType,
        [string] $LdapBaseDn,
        [string] $LdapBindType,
        [bool] $LdapCertificateValidation,

        # Picky
        [string] $PickyUrl,
        [string] $PickyApiKey,
        [bool] $PickyExternal,

        # Lucid
        [string] $LucidUrl,
        [string] $LucidApiKey,
        [string] $LucidAdminUsername,
        [string] $LucidAdminSecret,
        [bool] $LucidExternal,

        # NATS
        [string] $NatsUrl,
        [string] $NatsUsername,
        [string] $NatsPassword,
        [bool] $NatsExternal,
        
        # Redis
        [string] $RedisUrl,
        [string] $RedisPassword,
        [bool] $RedisExternal,

        # Docker
        [string] $DockerNetwork,
        [string] $DockerPlatform,
        [string] $DockerIsolation,
        [string] $DockerHost,
        [string] $SyslogServer,

        [switch] $Force
    )

    $ConfigPath = Find-WaykDenConfig -ConfigPath:$ConfigPath

    $config = Get-WaykDenConfig -ConfigPath:$ConfigPath

    New-Item -Path $ConfigPath -ItemType "Directory" -Force | Out-Null
    $ConfigFile = Join-Path $ConfigPath "wayk-den.yml"

    $properties = [WaykDenConfig].GetProperties() | ForEach-Object { $_.Name }
    foreach ($param in $PSBoundParameters.GetEnumerator()) {
        if ($properties -Contains $param.Key) {
            $config.($param.Key) = $param.Value
        }
    }

    Expand-WaykDenConfigKeys -Config:$config
 
    # always force overwriting wayk-den.yml when updating the config file
    ConvertTo-Yaml -Data (ConvertTo-SnakeCaseObject -Object $config) -OutFile $ConfigFile -Force

    Export-TraefikToml -ConfigPath:$ConfigPath
}

function Get-WaykDenConfig
{
    [CmdletBinding()]
    [OutputType('WaykDenConfig')]
    param(
        [string] $ConfigPath,
        [switch] $Expand
    )

    $ConfigPath = Find-WaykDenConfig -ConfigPath:$ConfigPath

    $ConfigFile = Join-Path $ConfigPath "wayk-den.yml"
    $ConfigData = Get-Content -Path $ConfigFile -Raw -ErrorAction Stop
    $yaml = ConvertFrom-Yaml -Yaml $ConfigData -UseMergingParser -AllDocuments -Ordered

    $config = [WaykDenConfig]::new()

    [WaykDenConfig].GetProperties() | ForEach-Object {
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
        Expand-WaykDenConfig $config
    }

    return $config
}

Export-ModuleMember -Function New-WaykDenConfig, Set-WaykDenConfig, Get-WaykDenConfig, `
    Set-WaykDenConfigPath, Get-WaykDenPath
