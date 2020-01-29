
function New-TraefikToml
{
    [OutputType('System.String')]
    param(
        [string] $Platform,
        [string] $ListenerUrl,
        [string] $DenLucidUrl,
        [string] $DenRouterUrl,
        [string] $DenServerUrl
    )

    $url = [System.Uri]::new($ListenerUrl)
    $Port = $url.Port
    $Protocol = $url.Scheme

    if ($Platform -eq "linux") {
        $PathSeparator = "/"
        $TraefikDataPath = "/etc/traefik"
    } else {
        $PathSeparator = "\"
        $TraefikDataPath = "c:\etc\traefik"
    }

    # note: .pem file should contain leaf cert + intermediate CA cert, in that order.

    $TraefikPort = $Port
    $TraefikEntrypoint = $Protocol
    $TraefikCertFile = $(@($TraefikDataPath, "den-server.pem") -Join $PathSeparator)
    $TraefikKeyFile = $(@($TraefikDataPath, "den-server.key") -Join $PathSeparator)

    $templates = @()

    $templates += '
logLevel = "INFO"

[file]

[entryPoints]
    [entryPoints.${TraefikEntrypoint}]
    address = ":${TraefikPort}"'

    if ($Protocol -eq 'https') {
        $templates += '
        [entryPoints.${TraefikEntrypoint}.tls]
            [entryPoints.${TraefikEntrypoint}.tls.defaultCertificate]
            certFile = "${TraefikCertFile}"
            keyFile = "${TraefikKeyFile}"'
    }

    $templates += '
        [entryPoints.${TraefikEntrypoint}.redirect]
        regex = "^http(s)?://([^/]+)/?`$"
        replacement = "http`$1://`$2/web"
    '

    $templates += '
[frontends]
    [frontends.lucid]
    passHostHeader = true
    backend = "lucid"
    entrypoints = ["${TraefikEntrypoint}"]
        [frontends.lucid.routes.lucid]
        rule = "PathPrefixStrip:/lucid"

    [frontends.lucidop]
    passHostHeader = true
    backend = "lucid"
    entrypoints = ["${TraefikEntrypoint}"]
        [frontends.lucidop.routes.lucidop]
        rule = "PathPrefix:/op"

    [frontends.lucidauth]
    passHostHeader = true
    backend = "lucid"
    entrypoints = ["${TraefikEntrypoint}"]
        [frontends.lucidauth.routes.lucidauth]
        rule = "PathPrefix:/auth"

    [frontends.router]
    passHostHeader = true
    backend = "router"
    entrypoints = ["${TraefikEntrypoint}"]
        [frontends.router.routes.router]
        rule = "PathPrefixStrip:/cow"

    [frontends.server]
    passHostHeader = true
    backend = "server"
    entrypoints = ["${TraefikEntrypoint}"]
'

    $templates += '
[backends]
    [backends.lucid]
        [backends.lucid.servers.lucid]
        url = "${DenLucidUrl}"
        weight = 10

    [backends.router]
        [backends.router.servers.router]
        url = "${DenRouterUrl}"
        method="drr"
        weight = 10

    [backends.server]
        [backends.server.servers.server]
        url = "${DenServerUrl}"
        weight = 10
        method="drr"
'

    $template = -Join $templates

    return Invoke-Expression "@`"`r`n$template`r`n`"@"
}
