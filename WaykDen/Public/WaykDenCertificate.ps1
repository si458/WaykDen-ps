
. "$PSScriptRoot/../Private/CertificateHelper.ps1"

function Import-WaykDenCertificate
{
    [CmdletBinding()]
    param(
        [string] $ConfigPath,
        [string] $CertificateFile,
        [string] $PrivateKeyFile,
        [string] $Password
    )

    $ConfigPath = Find-WaykDenConfig -ConfigPath:$ConfigPath

    $config = Get-WaykDenConfig -ConfigPath:$ConfigPath

    $result = Get-PemCertificate -CertificateFile:$CertificateFile `
        -PrivateKeyFile:$PrivateKeyFile -Password:$Password
        
    $CertificateData = $result.Certificate
    $PrivateKeyData = $result.PrivateKey

    $TraefikPath = Join-Path $ConfigPath "traefik"
    New-Item -Path $TraefikPath -ItemType "Directory" -Force | Out-Null

    $TraefikPemFile = Join-Path $TraefikPath "den-server.pem"
    $TraeficKeyFile = Join-Path $TraefikPath "den-server.key"

    Set-Content -Path $TraefikPemFile -Value $CertificateData -Force
    Set-Content -Path $TraeficKeyFile -Value $PrivateKeyData -Force
}

Export-ModuleMember -Function Import-WaykDenCertificate
