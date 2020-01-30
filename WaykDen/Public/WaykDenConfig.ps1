
. "$PSScriptRoot/../Private/CaseHelper.ps1"
. "$PSScriptRoot/../Private/YamlHelper.ps1"
. "$PSScriptRoot/../Private/TraefikHelper.ps1"
. "$PSScriptRoot/../Private/RandomGenerator.ps1"
. "$PSScriptRoot/../Private/CertificateHelper.ps1"

class WaykDenConfig
{
    # Server
    [string] $Realm
    [string] $ExternalUrl
    [string] $ListenerUrl
    [string] $ServerMode
    [string] $ServerCount

    # MongoDB
    [string] $MongoUrl

    # Jet
    [string] $JetRelayUrl

    # LDAP
    [string] $LdapServerUrl
    [string] $LdapUsername
    [string] $LdapPassword
    [string] $LdapUserGroup
    [string] $LdapServerType
    [string] $LdapBaseDn

    # NATS
    [string] $NatsUrl
    [string] $NatsUsername
    [string] $NatsPassword
    
    # Redis
    [string] $RedisUrl
    [string] $RedisPassword

    # Internal API keys
    [string] $DenApiKey
    [string] $PickyApiKey
    [string] $LucidApiKey
    [string] $LucidAdminUsername
    [string] $LucidAdminSecret

    # Internal settings
    [string] $DockerNetwork
    [string] $DockerPlatform
    [string] $SyslogServer
    [string] $MongoVolume
    [string] $JetServerUrl
    [string] $DenPickyUrl
    [string] $DenLucidUrl
    [string] $DenServerUrl
    [string] $DenRouterUrl
}

function Set-ConfigString
{
    param(
        [Parameter(Position=0)]
        $config,
        [Parameter(Position=1)]
        [string] $Name,
        [Parameter(Position=2)]
        [string] $Value
    )

    if (![string]::IsNullOrEmpty($Value)) {
        $config.$Name = $Value
    }
}

function Get-ConfigString
{
    [OutputType('System.String')]
    param(
        [Parameter(Position=0)]
        $yaml,
        [Parameter(Position=1)]
        [string] $Name
    )

    $Name = ConvertTo-SnakeCase -Value $Name

    if (![string]::IsNullOrEmpty($yaml.$Name)) {
        return ($yaml.$Name | Out-String).Trim()
    } else {
        return $null
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
    $DenPickyUrlDefault = "http://den-picky:12345"
    $DenLucidUrlDefault = "http://den-lucid:4242"
    $DenServerUrlDefault = "http://den-server:10255"
    $DenRouterUrlDefault = "http://den-server:4491"

    if ([string]::IsNullOrEmpty($config.DockerNetwork)) {
        $config.DockerNetwork = $DockerNetworkDefault
    }

    if ([string]::IsNullOrEmpty($config.DockerPlatform)) {
        if (Get-IsWindows) {
            $config.DockerPlatform = "windows"
        } else {
            $config.DockerPlatform = "linux"
        }
    }

    if ([string]::IsNullOrEmpty($config.ServerMode)) {
        $config.ServerMode = $ServerModeDefault
    }

    if ([string]::IsNullOrEmpty($config.ServerCount)) {
        $config.ServerCount = 1
    }

    if ([string]::IsNullOrEmpty($config.ListenerUrl)) {
        $config.ListenerUrl = $ListenerUrlDefault
    }

    if ([string]::IsNullOrEmpty($config.MongoUrl)) {
        $config.MongoUrl = $MongoUrlDefault
    }

    if ([string]::IsNullOrEmpty($config.MongoVolume)) {
        $config.MongoVolume = $MongoVolumeDefault
    }

    if ([string]::IsNullOrEmpty($config.JetServerUrl)) {
        $config.JetServerUrl = $JetServerUrlDefault
    }

    if ([string]::IsNullOrEmpty($config.JetRelayUrl)) {
        $config.JetRelayUrl = $JetRelayUrlDefault
    }

    if ([string]::IsNullOrEmpty($config.DenPickyUrl)) {
        $config.DenPickyUrl = $DenPickyUrlDefault
    }

    if ([string]::IsNullOrEmpty($config.DenLucidUrl)) {
        $config.DenLucidUrl = $DenLucidUrlDefault
    }

    if ([string]::IsNullOrEmpty($config.DenServerUrl)) {
        $config.DenServerUrl = $DenServerUrlDefault
    }

    if ([string]::IsNullOrEmpty($config.DenRouterUrl)) {
        $config.DenRouterUrl = $DenRouterUrlDefault
    }
}

function Export-TraefikToml()
{
    param(
        [string] $Path
    )

    if ([string]::IsNullOrEmpty($Path)) {
        $Path = Get-Location
    }

    $config = Get-WaykDenConfig -Path:$Path
    Expand-WaykDenConfig $config

    $TraefikPath = Join-Path $Path "traefik"
    New-Item -Path $TraefikPath -ItemType "Directory" -Force | Out-Null

    $TraefikTomlFile = Join-Path $TraefikPath "traefik.toml"

    $TraefikToml = New-TraefikToml -Platform $config.DockerPlatform -ListenerUrl $config.ListenerUrl `
        -DenLucidUrl $config.DenLucidUrl -DenRouterUrl $config.DenRouterUrl -DenServerUrl $config.DenServerUrl
    Set-Content -Path $TraefikTomlFile -Value $TraefikToml
}

function New-WaykDenConfig
{
    param(
        [string] $Path,
    
        # Server
        [Parameter(Mandatory=$true)]
        [string] $Realm,
        [Parameter(Mandatory=$true)]
        [string] $ExternalUrl,
        [string] $ListenerUrl,
        [string] $ServerMode,
        [string] $ServerCount,

        # MongoDB
        [string] $MongoUrl,

        # Jet
        [string] $JetRelayUrl,

        # LDAP
        [string] $LdapServerUrl,
        [string] $LdapUsername,
        [string] $LdapPassword,
        [string] $LdapUserGroup,
        [string] $LdapServerType,
        [string] $LdapBaseDn,

        # NATS
        [string] $NatsUrl,
        [string] $NatsUsername,
        [string] $NatsPassword,
        
        # Redis
        [string] $RedisUrl,
        [string] $RedisPassword,

        [switch] $Force
    )

    if ([string]::IsNullOrEmpty($Path)) {
        $Path = Get-Location
    }

    New-Item -Path $Path -ItemType "Directory" -Force | Out-Null
    $ConfigFile = Join-Path $Path "wayk-den.yml"

    $DenApiKey = New-RandomString -Length 32
    $PickyApiKey = New-RandomString -Length 32
    $LucidApiKey = New-RandomString -Length 32
    $LucidAdminUsername = New-RandomString -Length 16
    $LucidAdminSecret = New-RandomString -Length 10

    $DenServerPath = Join-Path $Path "den-server"
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
    
    # Server
    Set-ConfigString $config 'Realm' $Realm
    Set-ConfigString $config 'ExternalUrl' $ExternalUrl
    Set-ConfigString $config 'ListenerUrl' $ListenerUrl
    Set-ConfigString $config 'ServerMode' $ServerMode
    Set-ConfigString $config 'ServerCount' $ServerCount

    # MongoDB
    Set-ConfigString $config 'MongoUrl' $MongoUrl
    
    # Jet
    Set-ConfigString $config 'JetRelayUrl' $JetRelayUrl

    # LDAP
    Set-ConfigString $config 'LdapServerUrl' $LdapServerUrl
    Set-ConfigString $config 'LdapUsername' $LdapUsername
    Set-ConfigString $config 'LdapPassword' $LdapPassword
    Set-ConfigString $config 'LdapUserGroup' $LdapUserGroup
    Set-ConfigString $config 'LdapServerType' $LdapServerType
    Set-ConfigString $config 'LdapBaseDn' $LdapBaseDn

    # NATS
    Set-ConfigString $config 'NatsUrl' $NatsUrl
    Set-ConfigString $config 'NatsUsername' $NatsUsername
    Set-ConfigString $config 'NatsPassword' $NatsPassword

    # Redis
    Set-ConfigString $config 'RedisUrl' $RedisUrl
    Set-ConfigString $config 'RedisPassword' $RedisPassword

    # Internal API keys
    Set-ConfigString $config 'DenApiKey' $DenApiKey
    Set-ConfigString $config 'PickyApiKey' $PickyApiKey
    Set-ConfigString $config 'LucidApiKey' $LucidApiKey
    Set-ConfigString $config 'LucidAdminUsername' $LucidAdminUsername
    Set-ConfigString $config 'LucidAdminSecret' $LucidAdminSecret

    ConvertTo-Yaml -Data (ConvertTo-SnakeCaseObject -Object $config) -OutFile $ConfigFile -Force:$Force

    Export-TraefikToml -Path:$Path
}

function Set-WaykDenConfig
{
    param(
        [string] $Path,
    
        [string] $Realm,
        [string] $ExternalUrl,

        # Server
        [string] $ListenerUrl,
        [string] $ServerMode,
        [string] $ServerCount,

        # MongoDB
        [string] $MongoUrl,

        # Jet
        [string] $JetRelayUrl,

        # LDAP
        [string] $LdapServerUrl,
        [string] $LdapUsername,
        [string] $LdapPassword,
        [string] $LdapUserGroup,
        [string] $LdapServerType,
        [string] $LdapBaseDn,

        # NATS
        [string] $NatsUrl,
        [string] $NatsUsername,
        [string] $NatsPassword,
        
        # Redis
        [string] $RedisUrl,
        [string] $RedisPassword,

        [switch] $Force
    )

    if ([string]::IsNullOrEmpty($Path)) {
        $Path = Get-Location
    }

    $config = Get-WaykDenConfig -Path $Path

    New-Item -Path $Path -ItemType "Directory" -Force | Out-Null
    $ConfigFile = Join-Path $Path "wayk-den.yml"

    # Server
    Set-ConfigString $config 'Realm' $Realm
    Set-ConfigString $config 'ExternalUrl' $ExternalUrl
    Set-ConfigString $config 'ListenerUrl' $ListenerUrl
    Set-ConfigString $config 'ServerMode' $ServerMode
    Set-ConfigString $config 'ServerCount' $ServerCount

    # MongoDB
    Set-ConfigString $config 'MongoUrl' $MongoUrl
    
    # Jet
    Set-ConfigString $config 'JetRelayUrl' $JetRelayUrl

    # LDAP
    Set-ConfigString $config 'LdapServerUrl' $LdapServerUrl
    Set-ConfigString $config 'LdapUsername' $LdapUsername
    Set-ConfigString $config 'LdapPassword' $LdapPassword
    Set-ConfigString $config 'LdapUserGroup' $LdapUserGroup
    Set-ConfigString $config 'LdapServerType' $LdapServerType
    Set-ConfigString $config 'LdapBaseDn' $LdapBaseDn

    # NATS
    Set-ConfigString $config 'NatsUrl' $NatsUrl
    Set-ConfigString $config 'NatsUsername' $NatsUsername
    Set-ConfigString $config 'NatsPassword' $NatsPassword

    # Redis
    Set-ConfigString $config 'RedisUrl' $RedisUrl
    Set-ConfigString $config 'RedisPassword' $RedisPassword
 
    # always force overwriting wayk-den.yml when updating the config file
    ConvertTo-Yaml -Data (ConvertTo-SnakeCaseObject -Object $config) -OutFile $ConfigFile -Force

    Export-TraefikToml -Path:$Path
}

function Get-WaykDenConfig
{
    [OutputType('WaykDenConfig')]
    param(
        [string] $Path
    )

    if ([string]::IsNullOrEmpty($Path)) {
        $Path = Get-Location
    }

    $ConfigFile = Join-Path $Path "wayk-den.yml"
    $ConfigData = Get-Content -Path $ConfigFile -Raw
    $yaml = ConvertFrom-Yaml -Yaml $ConfigData -UseMergingParser -AllDocuments -Ordered

    $config = [WaykDenConfig]::new()
    
    # Server
    $config.Realm = Get-ConfigString $yaml 'Realm'
    $config.ExternalUrl = Get-ConfigString $yaml 'ExternalUrl'
    $config.ListenerUrl = Get-ConfigString $yaml 'ListenerUrl'
    $config.ServerMode = Get-ConfigString $yaml 'ServerMode'
    $config.ServerCount = Get-ConfigString $yaml 'ServerCount'

    # MongoDB
    $config.MongoUrl = Get-ConfigString $yaml 'MongoUrl'

    # Jet
    $config.JetRelayUrl = Get-ConfigString $yaml 'JetRelayUrl'

    # LDAP
    $config.LdapServerUrl = Get-ConfigString $yaml 'LdapServerUrl'
    $config.LdapUsername = Get-ConfigString $yaml 'LdapUsername'
    $config.LdapPassword = Get-ConfigString $yaml 'LdapPassword'
    $config.LdapUserGroup = Get-ConfigString $yaml 'LdapUserGroup'
    $config.LdapServerType = Get-ConfigString $yaml 'LdapServerType'
    $config.LdapBaseDn = Get-ConfigString $yaml 'LdapBaseDn'

    # NATS
    $config.NatsUrl = Get-ConfigString $yaml 'NatsUrl'
    $config.NatsUsername = Get-ConfigString $yaml 'NatsUsername'
    $config.NatsPassword = Get-ConfigString $yaml 'NatsPassword'

    # Redis
    $config.RedisUrl = Get-ConfigString $yaml 'RedisUrl'
    $config.RedisPassword = Get-ConfigString $yaml 'RedisPassword'

    # Internal API keys
    $config.DenApiKey = Get-ConfigString $yaml 'DenApiKey'
    $config.PickyApiKey = Get-ConfigString $yaml 'PickyApiKey'
    $config.LucidApiKey = Get-ConfigString $yaml 'LucidApiKey'
    $config.LucidAdminUsername = Get-ConfigString $yaml 'LucidAdminUsername'
    $config.LucidAdminSecret = Get-ConfigString $yaml 'LucidAdminSecret'

    return $config
}

Export-ModuleMember -Function New-WaykDenConfig, Set-WaykDenConfig, Get-WaykDenConfig
