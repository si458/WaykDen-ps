
. "$PSScriptRoot/../Private/PlatformHelper.ps1"
. "$PSScriptRoot/../Private/DockerHelper.ps1"
. "$PSScriptRoot/../Private/TraefikHelper.ps1"

function Get-WaykDenImage
{
    param(
        [string] $Platform
    )

    $images = if ($Platform -ne "windows") {
        [ordered]@{ # Linux containers
            "den-mongo" = "library/mongo:4.1-bionic";
            "den-lucid" = "devolutions/den-lucid:3.6.5-buster";
            "den-picky" = "devolutions/picky:4.2.1-buster";
            "den-server" = "devolutions/den-server:1.9.0-buster";
            "den-traefik" = "library/traefik:1.7";
            "den-redis" = "library/redis:5.0-buster";
            "den-nats" = "library/nats:2.1-linux";
        }
    } else {
        [ordered]@{ # Windows containers
            "den-mongo" = "devolutions/mongo:4.0.12-servercore-ltsc2019";
            "den-lucid" = "devolutions/den-lucid:3.6.5-servercore-ltsc2019";
            "den-picky" = "devolutions/picky:4.2.1-servercore-ltsc2019";
            "den-server" = "devolutions/den-server:1.9.0-servercore-ltsc2019";
            "den-traefik" = "sixeyed/traefik:v1.7.8-windowsservercore-ltsc2019";
        }
    }

    return $images
}

function Get-WaykDenService
{
    param(
        [string] $Path,
        [WaykDenConfig] $Config
    )

    if ([string]::IsNullOrEmpty($Path)) {
        $Path = Get-Location
    }

    $Platform = $config.DockerPlatform
    $images = Get-WaykDenImage -Platform:$Platform

    $Realm = $config.Realm
    $ExternalUrl = $config.ExternalUrl

    $url = [System.Uri]::new($config.ListenerUrl)
    $TraefikPort = $url.Port

    $MongoUrl = $config.MongoUrl
    $MongoVolume = $config.MongoVolume
    $DenNetwork = $config.DockerNetwork
    $JetServerUrl = $config.JetServerUrl
    $JetRelayUrl = $config.JetRelayUrl

    $DenApiKey = $config.DenApiKey
    $PickyApiKey = $config.PickyApiKey
    $LucidApiKey = $config.LucidApiKey
    $LucidAdminUsername = $config.LucidAdminUsername
    $LucidAdminSecret = $config.LucidAdminSecret

    $DenPickyUrl = $config.DenPickyUrl
    $DenLucidUrl = $config.DenLucidUrl
    $DenServerUrl = $config.DenServerUrl

    if ($Platform -eq "linux") {
        $PathSeparator = "/"
        $MongoDataPath = "/data/db"
        $TraefikDataPath = "/etc/traefik"
        $DenServerDataPath = "/etc/den-server"
    } else {
        $PathSeparator = "\"
        $MongoDataPath = "c:\data\db"
        $TraefikDataPath = "c:\etc\traefik"
        $DenServerDataPath = "c:\den-server"
    }

    $ServerCount = 1
    if (![string]::IsNullOrEmpty($config.ServerCount)) {
        if ([int] $config.ServerCount -gt 1) {
            $ServerCount = [int] $config.ServerCount
        }
    }

    $Services = @()

    # den-mongo service
    $DenMongo = [DockerService]::new()
    $DenMongo.ContainerName = 'den-mongo'
    $DenMongo.Image = $images[$DenMongo.ContainerName]
    $DenMongo.Platform = $Platform
    $DenMongo.Networks += $DenNetwork
    $DenMongo.Volumes = @("$MongoVolume`:$MongoDataPath")
    $Services += $DenMongo

    if (($config.ServerMode -eq 'Public') -or ($ServerCount -gt 1)) {

        if ([string]::IsNullOrEmpty($config.NatsUrl)) {
            $config.NatsUrl = "den-nats"
        }

        if ([string]::IsNullOrEmpty($config.NatsUsername)) {
            $config.NatsUsername = New-RandomString -Length 16
        }

        if ([string]::IsNullOrEmpty($config.NatsPassword)) {
            $config.NatsPassword = New-RandomString -Length 16
        }
    
        if ([string]::IsNullOrEmpty($config.RedisUrl)) {
            $config.RedisUrl = "den-redis"
        }

        if ([string]::IsNullOrEmpty($config.RedisPassword)) {
            $config.RedisPassword = New-RandomString -Length 16
        }

        # den-nats service
        $DenNats = [DockerService]::new()
        $DenNats.ContainerName = 'den-nats'
        $DenNats.Image = $images[$DenNats.ContainerName]
        $DenNats.Platform = $Platform
        $DenNats.Networks += $DenNetwork
        $DenNats.Command = "--user $($config.NatsUsername) --pass $($config.NatsPassword)"
        $Services += $DenNats

        # den-redis service
        $DenRedis = [DockerService]::new()
        $DenRedis.ContainerName = 'den-redis'
        $DenRedis.Image = $images[$DenRedis.ContainerName]
        $DenRedis.Platform = $Platform
        $DenRedis.Networks += $DenNetwork
        $DenRedis.Command = "redis-server --requirepass $($config.RedisPassword)"
        $Services += $DenRedis
    }

    # den-picky service
    $DenPicky = [DockerService]::new()
    $DenPicky.ContainerName = 'den-picky'
    $DenPicky.Image = $images[$DenPicky.ContainerName]
    $DenPicky.Platform = $Platform
    $DenPicky.DependsOn = @("den-mongo")
    $DenPicky.Networks += $DenNetwork
    $DenPicky.Environment = [ordered]@{
        "PICKY_REALM" = $Realm;
        "PICKY_API_KEY" = $PickyApiKey;
        "PICKY_DATABASE_URL" = $MongoUrl;
    }
    $Services += $DenPicky

    # den-lucid service
    $DenLucid = [DockerService]::new()
    $DenLucid.ContainerName = 'den-lucid'
    $DenLucid.Image = $images[$DenLucid.ContainerName]
    $DenLucid.Platform = $Platform
    $DenLucid.DependsOn = @("den-mongo")
    $DenLucid.Networks += $DenNetwork
    $DenLucid.Environment = [ordered]@{
        "LUCID_ADMIN__SECRET" = $LucidAdminSecret;
        "LUCID_ADMIN__USERNAME" = $LucidAdminUsername;
        "LUCID_AUTHENTICATION__KEY" = $LucidApiKey;
        "LUCID_DATABASE__URL" = $MongoUrl;
        "LUCID_TOKEN__ISSUER" = "$ExternalUrl/lucid";
        "LUCID_ACCOUNT__APIKEY" = $DenApiKey;
        "LUCID_ACCOUNT__LOGIN_URL" = "$DenServerUrl/account/login";
        "LUCID_ACCOUNT__REFRESH_USER_URL" = "$DenServerUrl/account/refresh";
        "LUCID_ACCOUNT__FORGOT_PASSWORD_URL" = "$DenServerUrl/account/forgot";
        "LUCID_ACCOUNT__SEND_ACTIVATION_EMAIL_URL" = "$DenServerUrl/account/activation";
    }
    $DenLucid.Healthcheck = [DockerHealthcheck]::new("curl -sS $DenLucidUrl/health")
    $Services += $DenLucid

    # den-server service
    $DenServer = [DockerService]::new()
    $DenServer.ContainerName = 'den-server'
    $DenServer.Image = $images[$DenServer.ContainerName]
    $DenServer.Platform = $Platform
    $DenServer.DependsOn = @("den-mongo", 'den-traefik')
    $DenServer.Networks += $DenNetwork
    $DenServer.Environment = [ordered]@{
        "PICKY_REALM" = $Realm;
        "PICKY_URL" = $DenPickyUrl;
        "PICKY_APIKEY" = $PickyApiKey; # will be changed to PICKY_API_KEY
        "DB_URL" = $MongoUrl; # will be changed to MONGO_URL
        "LUCID_AUTHENTICATION_KEY" = $LucidApiKey;
        "DEN_ROUTER_EXTERNAL_URL" = "$ExternalUrl/cow";
        "LUCID_INTERNAL_URL" = $DenLucidUrl;
        "LUCID_EXTERNAL_URL" = "$ExternalUrl/lucid";
        "DEN_LOGIN_REQUIRED" = "false";
        "DEN_PUBLIC_KEY_FILE" = @($DenServerDataPath, "den-public.pem") -Join $PathSeparator
        "DEN_PRIVATE_KEY_FILE" = @($DenServerDataPath, "den-private.key") -Join $PathSeparator
        "JET_SERVER_URL" = $JetServerUrl;
        "JET_RELAY_URL" = $JetRelayUrl;
        "DEN_API_KEY" = $DenApiKey;
    }
    $DenServer.Volumes = @("$Path/den-server:$DenServerDataPath`:ro")
    $DenServer.Command = "-l trace"
    $DenServer.Healthcheck = [DockerHealthcheck]::new("curl -sS $DenServerUrl/health")

    if ($config.ServerMode -eq 'Private') {
        $DenServer.Environment['AUDIT_TRAILS'] = "true"
        $DenServer.Command += " -m onprem"
    } elseif ($config.ServerMode -eq 'Public') {
        $DenServer.Command += " -m cloud"
    }

    if (![string]::IsNullOrEmpty($config.LdapServerUrl)) {
        $DenServer.Environment['LDAP_SERVER_URL'] = $config.LdapServerUrl
    }

    if (![string]::IsNullOrEmpty($config.LdapUsername)) {
        $DenServer.Environment['LDAP_USERNAME'] = $config.LdapUsername
    }

    if (![string]::IsNullOrEmpty($config.LdapPassword)) {
        $DenServer.Environment['LDAP_PASSWORD'] = $config.LdapPassword
    }

    if (![string]::IsNullOrEmpty($config.LdapUserGroup)) {
        $DenServer.Environment['LDAP_USER_GROUP'] = $config.LdapUserGroup
    }

    if (![string]::IsNullOrEmpty($config.LdapServerType)) {
        $DenServer.Environment['LDAP_SERVER_TYPE'] = $config.LdapServerType
    }

    if (![string]::IsNullOrEmpty($config.LdapBaseDn)) {
        $DenServer.Environment['LDAP_BASE_DN'] = $config.LdapBaseDn
    }

    if (![string]::IsNullOrEmpty($config.NatsUrl)) {
        $DenServer.Environment['NATS_HOST'] = $config.NatsUrl
    }

    if (![string]::IsNullOrEmpty($config.NatsUsername)) {
        $DenServer.Environment['NATS_USERNAME'] = $config.NatsUsername
    }

    if (![string]::IsNullOrEmpty($config.NatsPassword)) {
        $DenServer.Environment['NATS_PASSWORD'] = $config.NatsPassword
    }

    if (![string]::IsNullOrEmpty($config.RedisUrl)) {
        $DenServer.Environment['REDIS_HOST'] = $config.RedisUrl
    }

    if (![string]::IsNullOrEmpty($config.RedisPassword)) {
        $DenServer.Environment['REDIS_PASSWORD'] = $config.RedisPassword
    }

    if ($ServerCount -gt 1) {
        1 .. $ServerCount | % {
            $ServerIndex = $_
            $Instance = [DockerService]::new([DockerService]$DenServer)
            $Instance.ContainerName = "den-server-$ServerIndex"
            $Instance.Healthcheck.Test = $Instance.Healthcheck.Test -Replace "den-server", $Instance.ContainerName
            $Services += $Instance
        }
    } else {
        $Services += $DenServer
    }

    # den-traefik service
    $DenTraefik = [DockerService]::new()
    $DenTraefik.ContainerName = 'den-traefik'
    $DenTraefik.Image = $images[$DenTraefik.ContainerName]
    $DenTraefik.Platform = $Platform
    $DenTraefik.Networks += $DenNetwork
    $DenTraefik.Volumes = @("$Path/traefik:$TraefikDataPath")
    $DenTraefik.Command = ("--file --configFile=" + $(@($TraefikDataPath, "traefik.toml") -Join $PathSeparator))
    $DenTraefik.Ports = @("$TraefikPort`:$TraefikPort")
    $Services += $DenTraefik

    if ($config.SyslogServer) {
        foreach ($Service in $Services) {
            $Service.Logging = [DockerLogging]::new($config.SyslogServer)
        }
    }

    return $Services
}

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

function Get-DockerRunCommand
{
    [OutputType('string[]')]
    param(
        [DockerService] $Service
    )

    $cmd = @('docker', 'run')

    $cmd += "-d" # detached

    if ($Service.Networks) {
        foreach ($Network in $Service.Networks) {
            $cmd += "--network=$Network"
        }
    }

    if ($Service.Environment) {
        $Service.Environment.GetEnumerator() | foreach {
            $key = $_.Key
            $val = $_.Value
            $cmd += @("-e", "$key=$val")
        }
    }

    if ($Service.Volumes) {
        foreach ($Volume in $Service.Volumes) {
            $cmd += @("-v", $Volume)
        }
    }

    if ($Service.Ports) {
        foreach ($Port in $Service.Ports) {
            $cmd += @("-p", $Port)
        }
    }

    if ($Service.Healthcheck) {
        $Healthcheck = $Service.Healthcheck
        if (![string]::IsNullOrEmpty($Healthcheck.Interval)) {
            $cmd += "--health-interval=" + $Healthcheck.Interval
        }
        if (![string]::IsNullOrEmpty($Healthcheck.Timeout)) {
            $cmd += "--health-timeout=" + $Healthcheck.Timeout
        }
        if (![string]::IsNullOrEmpty($Healthcheck.Retries)) {
            $cmd += "--health-retries=" + $Healthcheck.Retries
        }
        if (![string]::IsNullOrEmpty($Healthcheck.StartPeriod)) {
            $cmd += "--health-start-period=" + $Healthcheck.StartPeriod
        }
        $cmd += $("--health-cmd=`'" + $Healthcheck.Test + "`'")
    }

    if ($Service.Logging) {
        $Logging = $Service.Logging
        $cmd += '--log-driver=' + $Logging.Driver

        $options = @()
        $Logging.Options.GetEnumerator() | foreach {
            $key = $_.Key
            $val = $_.Value
            $options += "$key=$val"
        }

        $options = $options -Join ","
        $cmd += "--log-opt=" + $options
    }

    $cmd += @('--name', $Service.ContainerName, $Service.Image)
    $cmd += $Service.Command

    return $cmd
}

function Start-DockerService
{
    param(
        [DockerService] $Service,
        [switch] $Remove,
        [switch] $Verbose
    )

    if (Get-ContainerExists -Name $Service.ContainerName) {
        if (Get-ContainerIsRunning -Name $Service.ContainerName) {
            docker stop $Service.ContainerName | Out-Null
        }

        if ($Remove) {
            docker rm $Service.ContainerName | Out-Null
        }
    }

    $RunCommand = (Get-DockerRunCommand -Service $Service) -Join " "

    if ($Verbose) {
        Write-Host $RunCommand
    }

    $id = Invoke-Expression $RunCommand

    if ($Service.Healthcheck) {
        Wait-ContainerHealthy -Name $Service.ContainerName | Out-Null
    }

    if (Get-ContainerIsRunning -Name $Service.ContainerName){
        Write-Host "$($Service.ContainerName) successfully started"
    } else {
        Write-Error -Message "Error starting $($Service.ContainerName)"
    }
}

function Start-WaykDen
{
    param(
        [string] $Path,
        [switch] $Verbose
    )

    $config = Get-WaykDenConfig -Path:$Path
    Expand-WaykDenConfig -Config $config

    $Platform = $config.DockerPlatform
    $Services = Get-WaykDenService -Path:$Path -Config $config

    # update traefik.toml
    Export-TraefikToml -Path:$Path

    # pull docker images
    foreach ($service in $services) {
        docker pull $service.Image | Out-Null
    }

    # create docker network
    New-DockerNetwork -Name $config.DockerNetwork -Platform $Platform -Force

    # create docker volume
    New-DockerVolume -Name $config.MongoVolume -Force

    # start containers
    foreach ($Service in $Services) {
        Start-DockerService -Service $Service -Remove -Verbose:$Verbose
    }
}

function Stop-WaykDen
{
    param(
        [string] $Path,
        [switch] $Remove
    )

    $config = Get-WaykDenConfig -Path:$Path
    Expand-WaykDenConfig -Config $config

    $Services = Get-WaykDenService -Path:$Path -Config $config

    # stop containers
    foreach ($Service in $Services) {
        Write-Host "Stopping $($Service.ContainerName)"
        docker stop $Service.ContainerName | Out-Null

        if ($Remove) {
            docker rm $Service.ContainerName | Out-Null
        }
    }
}

function Restart-WaykDen
{
    param(
        [string] $Path
    )

    Stop-WaykDen -Path:$Path
    Start-WaykDen -Path:$Path
}

Export-ModuleMember -Function Start-WaykDen, Stop-WaykDen, Restart-WaykDen
