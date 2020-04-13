
. "$PSScriptRoot/../Private/PlatformHelper.ps1"
. "$PSScriptRoot/../Private/DockerHelper.ps1"
. "$PSScriptRoot/../Private/TraefikHelper.ps1"
. "$PSScriptRoot/../Private/CmdletService.ps1"

function Get-WaykDenImage
{
    param(
        [string] $Platform
    )

    $images = if ($Platform -ne "windows") {
        [ordered]@{ # Linux containers
            "den-lucid" = "devolutions/den-lucid:3.6.6-buster-dev";
            "den-picky" = "devolutions/picky:4.2.1-buster";
            "den-server" = "devolutions/den-server:1.18.0-buster-dev";

            "den-mongo" = "library/mongo:4.2-bionic";
            "den-traefik" = "library/traefik:1.7";
            "den-nats" = "library/nats:2.1-linux";
            "den-redis" = "library/redis:5.0-buster";
        }
    } else {
        [ordered]@{ # Windows containers
            "den-lucid" = "devolutions/den-lucid:3.6.6-servercore-ltsc2019-dev";
            "den-picky" = "devolutions/picky:4.2.1-servercore-ltsc2019";
            "den-server" = "devolutions/den-server:1.18.0-servercore-ltsc2019-dev";

            "den-mongo" = "library/mongo:4.2-windowsservercore-1809";
            "den-traefik" = "library/traefik:1.7-windowsservercore-1809";
            "den-nats" = "library/nats:2.1-windowsservercore-1809";
            "den-redis" = ""; # not available
        }
    }

    return $images
}

function Get-HostInfo()
{
    param(
        [string] $Platform
    )

    $PSVersion = Get-PSVersion
    $CmdletVersion = Get-CmdletVersion
    $DockerVersion = Get-DockerVersion
    $DockerPlatform = $Platform
    $OsVersionInfo = Get-OsVersionInfo

    $images = Get-WaykDenImage -Platform:$Platform
    $DenServerImage = $images['den-server']
    $DenPickyImage = $images['den-picky']
    $DenLucidImage = $images['den-lucid']
    $TraefikImage = $images['den-traefik']
    $MongoImage = $images['den-mongo']

    return [PSCustomObject]@{
        PSVersion = $PSVersion
        CmdletVersion = $CmdletVersion
        DockerVersion = $DockerVersion
        DockerPlatform = $DockerPlatform
        OsVersionInfo = $OsVersionInfo

        DenServerImage = $DenServerImage
        DenPickyImage = $DenPickyImage
        DenLucidImage = $DenLucidImage
        TraefikImage = $TraefikImage
        MongoImage = $MongoImage
    }
}

function Get-WaykDenService
{
    param(
        [string] $ConfigPath,
        [WaykDenConfig] $Config
    )

    $ConfigPath = Find-WaykDenConfig -ConfigPath:$ConfigPath

    $Platform = $config.DockerPlatform
    $Isolation = $config.DockerIsolation
    $images = Get-WaykDenImage -Platform:$Platform

    $Realm = $config.Realm
    $ExternalUrl = $config.ExternalUrl
    $ListenerUrl = $config.ListenerUrl

    $url = [System.Uri]::new($ListenerUrl)
    $TraefikPort = $url.Port
    $ListenerScheme = $url.Scheme

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

    $PickyUrl = $config.PickyUrl
    $LucidUrl = $config.LucidUrl
    $DenServerUrl = $config.DenServerUrl

    $RustBacktrace = "1"

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
    if ([int] $config.ServerCount -gt 1) {
        $ServerCount = [int] $config.ServerCount
    }

    $Services = @()

    # den-mongo service
    $DenMongo = [DockerService]::new()
    $DenMongo.ContainerName = 'den-mongo'
    $DenMongo.Image = $images[$DenMongo.ContainerName]
    $DenMongo.Platform = $Platform
    $DenMongo.Isolation = $Isolation
    $DenMongo.TargetPorts = @(27017)
    if ($DenNetwork -NotMatch "none") {
        $DenMongo.Networks += $DenNetwork
    } else {
        $DenMongo.PublishAll = $true
    }
    $DenMongo.Volumes = @("$MongoVolume`:$MongoDataPath")
    $DenMongo.External = $config.MongoExternal
    $Services += $DenMongo

    if (($config.ServerMode -eq 'Public') -or ($ServerCount -gt 1)) {

        if (-Not $config.NatsUrl) {
            $config.NatsUrl = "den-nats"
        }

        if (-Not $config.NatsUsername) {
            $config.NatsUsername = New-RandomString -Length 16
        }

        if (-Not $config.NatsPassword) {
            $config.NatsPassword = New-RandomString -Length 16
        }
    
        if (-Not $config.RedisUrl) {
            $config.RedisUrl = "den-redis"
        }

        if (-Not $config.RedisPassword) {
            $config.RedisPassword = New-RandomString -Length 16
        }

        # den-nats service
        $DenNats = [DockerService]::new()
        $DenNats.ContainerName = 'den-nats'
        $DenNats.Image = $images[$DenNats.ContainerName]
        $DenNats.Platform = $Platform
        $DenNats.Isolation = $Isolation
        if ($DenNetwork -NotMatch "none") {
            $DenNats.Networks += $DenNetwork
        } else {
            $DenNats.PublishAll = $true
        }
        $DenNats.Command = "--user $($config.NatsUsername) --pass $($config.NatsPassword)"
        $DenNats.External = $config.NatsExternal
        $Services += $DenNats

        # den-redis service
        $DenRedis = [DockerService]::new()
        $DenRedis.ContainerName = 'den-redis'
        $DenRedis.Image = $images[$DenRedis.ContainerName]
        $DenRedis.Platform = $Platform
        $DenRedis.Isolation = $Isolation
        if ($DenNetwork -NotMatch "none") {
            $DenRedis.Networks += $DenNetwork
        } else {
            $DenRedis.PublishAll = $true
        }
        $DenRedis.Command = "redis-server --requirepass $($config.RedisPassword)"
        $DenRedis.External = $config.RedisExternal
        $Services += $DenRedis
    }

    # den-picky service
    $DenPicky = [DockerService]::new()
    $DenPicky.ContainerName = 'den-picky'
    $DenPicky.Image = $images[$DenPicky.ContainerName]
    $DenPicky.Platform = $Platform
    $DenPicky.Isolation = $Isolation
    $DenPicky.DependsOn = @("den-mongo")
    $DenPicky.TargetPorts = @(12345)
    if ($DenNetwork -NotMatch "none") {
        $DenPicky.Networks += $DenNetwork
    } else {
        $DenPicky.PublishAll = $true
    }
    $DenPicky.Environment = [ordered]@{
        "PICKY_REALM" = $Realm;
        "PICKY_API_KEY" = $PickyApiKey;
        "PICKY_DATABASE_URL" = $MongoUrl;
        "RUST_BACKTRACE" = $RustBacktrace;
    }
    $DenPicky.External = $config.PickyExternal
    $Services += $DenPicky

    # den-lucid service
    $DenLucid = [DockerService]::new()
    $DenLucid.ContainerName = 'den-lucid'
    $DenLucid.Image = $images[$DenLucid.ContainerName]
    $DenLucid.Platform = $Platform
    $DenLucid.Isolation = $Isolation
    $DenLucid.DependsOn = @("den-mongo")
    $DenLucid.TargetPorts = @(4242)
    if ($DenNetwork -NotMatch "none") {
        $DenLucid.Networks += $DenNetwork
    } else {
        $DenLucid.PublishAll = $true
    }
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
        "LUCID_LOCALHOST_LISTENER" = $ListenerScheme;
        "RUST_BACKTRACE" = $RustBacktrace;
    }
    $DenLucid.Healthcheck = [DockerHealthcheck]::new("curl -sS $LucidUrl/health")
    $DenLucid.External = $config.LucidExternal
    $Services += $DenLucid

    # den-server service
    $DenServer = [DockerService]::new()
    $DenServer.ContainerName = 'den-server'
    $DenServer.Image = $images[$DenServer.ContainerName]
    $DenServer.Platform = $Platform
    $DenServer.Isolation = $Isolation
    $DenServer.DependsOn = @("den-mongo", 'den-traefik')
    $DenServer.TargetPorts = @(4491, 10255)
    if ($DenNetwork -NotMatch "none") {
        $DenServer.Networks += $DenNetwork
    } else {
        $DenServer.PublishAll = $true
    }
    $DenServer.Environment = [ordered]@{
        "DEN_LISTENER_URL" = $ListenerUrl;
        "DEN_EXTERNAL_URL" = $ExternalUrl;
        "PICKY_REALM" = $Realm;
        "PICKY_URL" = $PickyUrl;
        "PICKY_EXTERNAL_URL" = "$ExternalUrl/picky";
        "PICKY_API_KEY" = $PickyApiKey;
        "MONGO_URL" = $MongoUrl;
        "LUCID_AUTHENTICATION_KEY" = $LucidApiKey;
        "DEN_ROUTER_EXTERNAL_URL" = "$ExternalUrl/cow";
        "LUCID_INTERNAL_URL" = $LucidUrl;
        "LUCID_EXTERNAL_URL" = "$ExternalUrl/lucid";
        "DEN_LOGIN_REQUIRED" = "false";
        "DEN_PUBLIC_KEY_FILE" = @($DenServerDataPath, "den-public.pem") -Join $PathSeparator
        "DEN_PRIVATE_KEY_FILE" = @($DenServerDataPath, "den-private.key") -Join $PathSeparator
        "DEN_HOST_INFO_FILE" = @($DenServerDataPath, "host_info.json") -Join $PathSeparator
        "JET_SERVER_URL" = $JetServerUrl;
        "JET_RELAY_URL" = $JetRelayUrl;
        "DEN_API_KEY" = $DenApiKey;
        "RUST_BACKTRACE" = $RustBacktrace;
    }
    $DenServer.Volumes = @("$ConfigPath/den-server:$DenServerDataPath`:ro")
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

    if (![string]::IsNullOrEmpty($config.LdapServerIp)) {
        $DenServer.Environment['LDAP_SERVER_IP'] = $config.LdapServerIp
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

        if ($config.LdapCertificateValidation) {
            $DenServer.Environment['LDAP_CERTIFICATE_VALIDATION'] = 'true'
        } else {
            $DenServer.Environment['LDAP_CERTIFICATE_VALIDATION'] = 'false'
        }
    }

    if (![string]::IsNullOrEmpty($config.LdapBaseDn)) {
        $DenServer.Environment['LDAP_BASE_DN'] = $config.LdapBaseDn
    }

    if (![string]::IsNullOrEmpty($config.LdapBindType)) {
        $DenServer.Environment['LDAP_BIND_TYPE'] = $config.LdapBindType
    }

    if (Test-Path $(Join-Path $ConfigPath 'den-server/ldap-root-ca.pem')) {
        $DenServer.Environment['LDAP_TRUSTED_ROOT_CA_FILE'] = `
            @($DenServerDataPath, "ldap-root-ca.pem") -Join $PathSeparator
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

    $DenServer.External = $config.ServerExternal

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
    $DenTraefik.Isolation = $Isolation
    $DenTraefik.TargetPorts = @($TraefikPort)
    if ($DenNetwork -NotMatch "none") {
        $DenTraefik.Networks += $DenNetwork
    }
    $DenTraefik.PublishAll = $true
    $DenTraefik.Volumes = @("$ConfigPath/traefik:$TraefikDataPath")
    $DenTraefik.Command = ("--file --configFile=" + $(@($TraefikDataPath, "traefik.toml") -Join $PathSeparator))
    $Services += $DenTraefik

    if ($config.SyslogServer) {
        foreach ($Service in $Services) {
            $Service.Logging = [DockerLogging]::new($config.SyslogServer)
        }
    }

    return $Services
}

function Get-DockerRunCommand
{
    [OutputType('string[]')]
    param(
        [DockerService] $Service
    )

    $cmd = @('docker', 'run')

    $cmd += @('--name', $Service.ContainerName)

    $cmd += "-d" # detached
    
    $cmd += @('--restart', 'on-failure') # restart container if failure due to crash

    if ($Service.Platform -eq 'windows') {
        if ($Service.Isolation -eq 'hyperv') {
            $cmd += "--isolation=hyperv"
        }
    }

    if ($Service.Networks) {
        foreach ($Network in $Service.Networks) {
            $cmd += "--network=$Network"
        }
    }

    if ($Service.Environment) {
        $Service.Environment.GetEnumerator() | foreach {
            $key = $_.Key
            $val = $_.Value
            $cmd += @("-e", "`"$key=$val`"")
        }
    }

    if ($Service.Volumes) {
        foreach ($Volume in $Service.Volumes) {
            $cmd += @("-v", "`"$Volume`"")
        }
    }

    if ($Service.PublishAll) {
        foreach ($TargetPort in $Service.TargetPorts) {
            $cmd += @("-p", "$TargetPort`:$TargetPort")
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

    $cmd += $Service.Image
    $cmd += $Service.Command

    return $cmd
}

function Start-DockerService
{
    [CmdletBinding()]
    param(
        [DockerService] $Service,
        [switch] $Remove
    )

    if ($Service.External) {
        return # service should already be running
    }

    if (Get-ContainerExists -Name $Service.ContainerName) {
        if (Get-ContainerIsRunning -Name $Service.ContainerName) {
            Stop-Container -Name $Service.ContainerName
        }

        if ($Remove) {
            Remove-Container -Name $Service.ContainerName
        }
    }

    # Workaround for https://github.com/docker-library/mongo/issues/385
    if (($Service.Platform -eq 'Windows') -and ($Service.ContainerName -Like '*mongo')) {
        $VolumeName = $($Service.Volumes[0] -Split ':', 2)[0]
        $Volume = $(docker volume inspect $VolumeName) | ConvertFrom-Json
        $WiredTigerLock = Join-Path $Volume.MountPoint 'WiredTiger.lock'
        if (Test-Path $WiredTigerLock) {
            Write-Host "Removing $WiredTigerLock"
            Remove-Item $WiredTigerLock -Force
        }
    }

    $RunCommand = (Get-DockerRunCommand -Service $Service) -Join " "

    Write-Host "Starting $($Service.ContainerName)"
    Write-Verbose $RunCommand

    $id = Invoke-Expression $RunCommand

    if ($Service.Healthcheck) {
        Wait-ContainerHealthy -Name $Service.ContainerName | Out-Null
    }

    if (Get-ContainerIsRunning -Name $Service.ContainerName) {
        Write-Host "$($Service.ContainerName) successfully started"
    } else {
        throw "Error starting $($Service.ContainerName)"
    }
}

function Test-DockerHost
{
    [CmdletBinding()]
    param()

    if (Get-IsWindows) {
        $DnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 | `
            Select-Object -Unique -ExpandProperty ServerAddresses

        if ($DnsServers -Contains '127.0.0.1') {
            Write-Warning "A DNS server with address 127.0.0.1 is configured on the host."
            Write-Warning "This is known to cause DNS resolution issues inside containers."
            Write-Warning "Please use the host IP address from the host network instead."
        }

        $SEP = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" | `
            ForEach-Object { Get-ItemProperty $_.PSPath } | `
            Where-Object { $_ -Match 'Symantec Endpoint Protection' }

        if ($SEP) {
            Write-Warning "Symantec Endpoint Protection (SEP) has been detected."
            Write-Warning "It is known to cause several issues with Docker for Windows."
            Write-Warning "Removing the 'Application and Device Control' (ADC) component is recommended."
            Write-Warning "Please refer to the following article for the relevant exclusions:"
            Write-Warning "https://knowledge.broadcom.com/external/article?legacyId=TECH246815"
            Write-Warning "You should also add %ProgramData%\docker to the exclusion list:"
            Write-Warning "https://docs.docker.com/engine/security/antivirus/"
            Write-Warning "At last, you can refer to the following blog article for further guidance:"
            Write-Warning "https://mdaslam.wordpress.com/2017/05/23/docker-container-windows-2016-server-with-sep-symantec-endpoint-protection/"
        }
    }
}

function Update-WaykDen
{
    [CmdletBinding()]
    param(
        [string] $ConfigPath
    )

    $ConfigPath = Find-WaykDenConfig -ConfigPath:$ConfigPath
    $config = Get-WaykDenConfig -ConfigPath:$ConfigPath
    Expand-WaykDenConfig -Config $config

    $Platform = $config.DockerPlatform
    $Services = Get-WaykDenService -ConfigPath:$ConfigPath -Config $config

    foreach ($service in $services) {
        Request-ContainerImage -Name $Service.Image
    }
}

function Start-WaykDen
{
    [CmdletBinding()]
    param(
        [string] $ConfigPath,
        [switch] $SkipPull
    )

    $ConfigPath = Find-WaykDenConfig -ConfigPath:$ConfigPath
    $config = Get-WaykDenConfig -ConfigPath:$ConfigPath
    Expand-WaykDenConfig -Config $config

    Test-DockerHost

    $Platform = $config.DockerPlatform
    $Services = Get-WaykDenService -ConfigPath:$ConfigPath -Config $config

    # update traefik.toml
    Export-TraefikToml -ConfigPath:$ConfigPath

    $HostInfo = Get-HostInfo -Platform:$Platform
    Export-HostInfo -ConfigPath:$ConfigPath -HostInfo $HostInfo

    if (-Not $SkipPull) {
        # pull docker images only if they are not cached locally
        foreach ($service in $services) {
            if (-Not (Get-ContainerImageId -Name $Service.Image)) {
                Request-ContainerImage -Name $Service.Image
            }
        }
    }

    # create docker network
    New-DockerNetwork -Name $config.DockerNetwork -Platform $Platform -Force

    # create docker volume
    New-DockerVolume -Name $config.MongoVolume -Force

    # start containers
    foreach ($Service in $Services) {
        Start-DockerService -Service $Service -Remove
    }
}

function Stop-WaykDen
{
    [CmdletBinding()]
    param(
        [string] $ConfigPath,
        [switch] $Remove
    )

    $ConfigPath = Find-WaykDenConfig -ConfigPath:$ConfigPath
    $config = Get-WaykDenConfig -ConfigPath:$ConfigPath
    Expand-WaykDenConfig -Config $config

    $Services = Get-WaykDenService -ConfigPath:$ConfigPath -Config $config

    # stop containers
    foreach ($Service in $Services) {
        if ($Service.External) {
            continue
        }

        Write-Host "Stopping $($Service.ContainerName)"
        Stop-Container -Name $Service.ContainerName -Quiet

        if ($Remove) {
            Remove-Container -Name $Service.ContainerName
        }
    }
}

function Restart-WaykDen
{
    [CmdletBinding()]
    param(
        [string] $ConfigPath
    )

    $ConfigPath = Find-WaykDenConfig -ConfigPath:$ConfigPath
    Stop-WaykDen -ConfigPath:$ConfigPath
    Start-WaykDen -ConfigPath:$ConfigPath
}

function Get-WaykDenServiceDefinition()
{
    $ServiceName = "WaykDen"
    $ModuleName = "WaykDen"
    $DisplayName = "Wayk Den"
    $CompanyName = "Devolutions"
    $Description = "Wayk Den service"

    return [PSCustomObject]@{
        ServiceName = $ServiceName
        DisplayName = $DisplayName
        Description = $Description
        CompanyName = $CompanyName
        ModuleName = $ModuleName
        StartCommand = "Start-WaykDen"
        StopCommand = "Stop-WaykDen"
        WorkingDir = "%ProgramData%\${CompanyName}\${DisplayName}"
    }
}

function Register-WaykDenService
{
    [CmdletBinding()]
    param(
        [string] $ServicePath,
        [switch] $Force
    )

    $Definition = Get-WaykDenServiceDefinition

    if ($ServicePath) {
        $Definition.WorkingDir = $ServicePath
    }

    Register-CmdletService -Definition $Definition -Force:$Force

    $ServiceName = $Definition.ServiceName
    $ServicePath = [System.Environment]::ExpandEnvironmentVariables($Definition.WorkingDir)
    Write-Host "`"$ServiceName`" service has been installed to `"$ServicePath`""
}

function Unregister-WaykDenService
{
    [CmdletBinding()]
    param(
        [string] $ServicePath,
        [switch] $Force
    )

    $Definition = Get-WaykDenServiceDefinition

    if ($ServicePath) {
        $Definition.WorkingDir = $ServicePath
    }

    Unregister-CmdletService -Definition $Definition -Force:$Force
}

Export-ModuleMember -Function Start-WaykDen, Stop-WaykDen, Restart-WaykDen, `
    Update-WaykDen, Register-WaykDenService, Unregister-WaykDenService
