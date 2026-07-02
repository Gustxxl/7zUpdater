
$ErrorActionPreference = "Stop"

$scriptUrl = "https://raw.githubusercontent.com/Gustxxl/7zUpdater/refs/heads/main/7zUpdater.ps1"

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    Write-Host "Restarting script as Administrator..."

    $elevatedCommand = "irm '$scriptUrl' | iex"

    $arguments = @(
        "-NoProfile"
        "-ExecutionPolicy", "Bypass"
        "-Command", $elevatedCommand
    )

    Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs
    exit 0
}

$downloadPageUrl = "https://www.7-zip.org/download.html"
$installerPath = Join-Path $env:TEMP "7zip-installer.exe"
$sevenZipExe = "C:\Program Files\7-Zip\7z.exe"

function Get-7ZipVersion {
    if (Test-Path $sevenZipExe) {
        $versionOutput = (& $sevenZipExe) -join "`n"

        $match = [regex]::Match($versionOutput, "7-Zip\s+(\d+\.\d+)")
        if ($match.Success) {
            return [version]$match.Groups[1].Value
        }
    }

    return $null
}

function Convert-7ZipLinkVersionToVersion {
    param (
        [Parameter(Mandatory)]
        [int]$VersionNum
    )

    $major = [math]::Floor($VersionNum / 100)
    $minor = $VersionNum % 100

    return [version]("{0}.{1:D2}" -f $major, $minor)
}

try {
    Write-Host "Fetching the latest 7-Zip download URL..."
    $downloadPageContent = Invoke-WebRequest -Uri $downloadPageUrl -UseBasicParsing

    $candidates = $downloadPageContent.Links |
        Where-Object { $_.href -match "^/?a/7z(\d+)-x64\.exe$" } |
        ForEach-Object {
            [void]($_.href -match "^/?a/7z(\d+)-x64\.exe$")

            $versionNum = [int]$matches[1]

            [PSCustomObject]@{
                Href       = $_.href
                VersionNum = $versionNum
                Version    = Convert-7ZipLinkVersionToVersion -VersionNum $versionNum
            }
        } |
        Sort-Object VersionNum -Descending

    if (-not $candidates) {
        Write-Host "Could not find a download link on the page. Aborting."
        exit 1
    }

    $latest = $candidates[0]
    $downloadUrl = [System.Uri]::new([System.Uri]$downloadPageUrl, $latest.Href).AbsoluteUri

    $currentVersion = Get-7ZipVersion

    if ($currentVersion) {
        Write-Host "Current 7-Zip version: $currentVersion (x64)"
    } else {
        Write-Host "7-Zip is not currently installed in the default x64 path."
    }

    Write-Host "Latest available 7-Zip version: $($latest.Version) (x64)"

    if ($currentVersion -and $currentVersion -ge $latest.Version) {
        Write-Host "7-Zip is already up to date. No update needed."
        exit 0
    }

    Write-Host "Downloading 7-Zip from $downloadUrl..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath

    if (-not (Test-Path $installerPath)) {
        Write-Host "Installer was not downloaded. Aborting."
        exit 1
    }

    Write-Host "Installing 7-Zip..."
    $process = Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        Write-Host "7-Zip installer exited with code $($process.ExitCode)."
        exit $process.ExitCode
    }

    $newVersion = Get-7ZipVersion

    if ($newVersion) {
        Write-Host "New 7-Zip version: $newVersion (x64)"
    } else {
        Write-Host "Could not detect the installed 7-Zip version after installation."
        exit 1
    }

    if ($newVersion -ge $latest.Version) {
        Write-Host "7-Zip successfully installed or updated to version $newVersion."
    } else {
        Write-Host "7-Zip installation completed, but detected version is lower than expected."
        Write-Host "Expected: $($latest.Version)"
        Write-Host "Detected: $newVersion"
        exit 1
    }
}
catch {
    Write-Host "Error: $($_.Exception.Message)"
    exit 1
}
finally {
    if (Test-Path $installerPath) {
        Write-Host "Cleaning up installer file..."
        Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    }
}
