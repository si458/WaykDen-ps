
. "$PSScriptRoot/../Private/CertificateHelper.ps1"

function Import-WaykDenCertificate
{
    param(
        [string] $Path,

        [string] $CertificateFile,
        [string] $PrivateKeyFile,
        [string] $Password
    )

    if ([string]::IsNullOrEmpty($Path)) {
        $Path = Get-Location
    }

    $config = Get-WaykDenConfig -Path:$Path

    $result = Get-PemCertificate -CertificateFile:$CertificateFile `
        -PrivateKeyFile:$PrivateKeyFile -Password:$Password
        
    $CertificateData = $result.Certificate
    $PrivateKeyData = $result.PrivateKey

    $TraefikPath = Join-Path $Path "traefik"
    New-Item -Path $TraefikPath -ItemType "Directory" -Force | Out-Null

    $TraefikPemFile = Join-Path $TraefikPath "den-server.pem"
    $TraeficKeyFile = Join-Path $TraefikPath "den-server.key"

    Set-Content -Path $TraefikPemFile -Value $CertificateData -Force
    Set-Content -Path $TraeficKeyFile -Value $PrivateKeyData -Force
}

Export-ModuleMember -Function Import-WaykDenCertificate
