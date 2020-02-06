
. "$PSScriptRoot/../Private/DockerHelper.ps1"

function Backup-WaykDenData
{
    [CmdletBinding()]
    param(
        [string] $ConfigPath,
        [string] $BackupPath
    )

    $ConfigPath = Find-WaykDenConfig -ConfigPath:$ConfigPath

    $config = Get-WaykDenConfig -ConfigPath:$ConfigPath
    Expand-WaykDenConfig -Config $config

    $Platform = $config.DockerPlatform
    $Services = Get-WaykDenService -ConfigPath:$ConfigPath -Config $config

    $Service = ($Services | Where-Object { $_.ContainerName -Like '*mongo' })[0]
    $container = $Service.ContainerName

    if ($Platform -eq "linux") {
        $PathSeparator = "/"
        $TempPath = "/tmp"
    } else {
        $PathSeparator = "\"
        $TempPath = "C:\temp"
    }

    if (-Not $BackupPath) {
        $BackupPath = Get-Location
    }

    $BackupFileName = "den-mongo.tgz"
    if (($BackupPath -match ".tgz") -or ($BackupPath -match ".tar.gz")) {
        $BackupFileName = Split-Path -Path $BackupPath -Leaf
    } else {
        $BackupPath = Join-Path $BackupPath $BackupFileName
    }

    $TempBackupPath = @($TempPath, $BackupFileName) -Join $PathSeparator

    # make sure parent output directory exists
    New-Item -Path $(Split-Path -Path $BackupPath) -ItemType "Directory" -Force | Out-Null

    $args = @('docker', 'exec', $container, 'mongodump', '--gzip', "--archive=${TempBackupPath}")
    $cmd = $args -Join " "
    Write-Verbose $cmd
    Invoke-Expression $cmd

    $args = @('docker', 'cp', "$container`:$TempBackupPath", $BackupPath)
    $cmd = $args -Join " "
    Write-Verbose $cmd
    Invoke-Expression $cmd
}

function Restore-WaykDenData
{
    [CmdletBinding()]
    param(
        [string] $ConfigPath,
        [string] $BackupPath
    )

    $ConfigPath = Find-WaykDenConfig -ConfigPath:$ConfigPath

    $config = Get-WaykDenConfig -ConfigPath:$ConfigPath
    Expand-WaykDenConfig -Config $config

    $Platform = $config.DockerPlatform
    $Services = Get-WaykDenService -ConfigPath:$ConfigPath -Config $config

    $Service = ($Services | Where-Object { $_.ContainerName -Like '*mongo' })[0]
    $ContainerName = $Service.ContainerName

    if ($Platform -eq "linux") {
        $PathSeparator = "/"
        $TempPath = "/tmp"
    } else {
        $PathSeparator = "\"
        $TempPath = "C:\temp"
    }

    $BackupFileName = "den-mongo.tgz"

    if (($BackupPath -match ".tgz") -or ($BackupPath -match ".tar.gz")) {
        $BackupFileName = Split-Path -Path $BackupPath -Leaf
    } else {
        $BackupPath = Join-Path $BackupPath $BackupFileName
    }

    $TempBackupPath = @($TempPath, $BackupFileName) -Join $PathSeparator

    if (-Not (Get-ContainerIsRunning -Name $ContainerName)) {
        Start-DockerService $Service
    }

    if (-Not (Test-Path -Path $BackupPath -PathType 'Leaf')) {
        throw "$BackupPath does not exist"
    }

    $args = @('docker', 'cp', $BackupPath, "$ContainerName`:$TempBackupPath")
    $cmd = $args -Join " "
    Write-Verbose $cmd
    Invoke-Expression $cmd

    $args = @('docker', 'exec', $ContainerName, 'mongorestore', '--drop', '--gzip', "--archive=${TempBackupPath}")
    $cmd = $args -Join " "
    Write-Verbose $cmd
    Invoke-Expression $cmd
}

Export-ModuleMember -Function Backup-WaykDenData, Restore-WaykDenData
