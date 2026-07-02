
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

    Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$elevatedCommand`"" `
        -Verb RunAs

    exit 0
}

$downloadPageUrl = "https://www.7-zip.org/download.html"
$installerPath = Join-Path $env:TEMP "7zip-installer.exe"
$sevenZipExePaths = @(
    "C:\Program Files\7-Zip\7z.exe",
    "C:\Program Files (x86)\7-Zip\7z.exe"
)

function Get-7ZipExePath {
    foreach ($path in $sevenZipExePaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    return $null
}

function Get-7ZipVersion {
    $sevenZipExe = Get-7ZipExePath

    if ($sevenZipExe) {
        $versionOutput = (& $sevenZipExe) -join "`n"

        $match = [regex]::Match($versionOutput, "7-Zip\s+(\d+\.\d+)")
        if ($match.Success) {
            return [version]$match.Groups[1].Value
        }
    }

    return $null
}

function Convert-VersionToInstallerNumber {
    param (
        [Parameter(Mandatory)]
        [version]$Version
    )

    return "{0}{1:D2}" -f $Version.Major, $Version.Minor
}

try {
    Write-Host "Fetching official 7-Zip download page..."
    $downloadPageContent = Invoke-WebRequest `
        -Uri $downloadPageUrl `
        -UseBasicParsing `
        -Headers @{
            "Cache-Control" = "no-cache"
            "Pragma"        = "no-cache"
        }

    $html = $downloadPageContent.Content

    $latestVersionMatch = [regex]::Match(
        $html,
        "Download\s+7-Zip\s+(\d+\.\d+)",
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if (-not $latestVersionMatch.Success) {
        Write-Host "Could not detect the latest 7-Zip version from the official page."
        exit 1
    }

    $latestVersion = [version]$latestVersionMatch.Groups[1].Value
    $installerVersionNumber = Convert-VersionToInstallerNumber -Version $latestVersion
    $downloadUrl = "https://www.7-zip.org/a/7z$installerVersionNumber-x64.exe"

    $currentVersion = Get-7ZipVersion
    $currentExePath = Get-7ZipExePath

    if ($currentVersion) {
        Write-Host "Current 7-Zip version: $currentVersion"
        Write-Host "Current 7-Zip path: $currentExePath"
    } else {
        Write-Host "7-Zip is not currently installed in the standard Program Files paths."
    }

    Write-Host "Latest official 7-Zip version: $latestVersion"
    Write-Host "Expected installer URL: $downloadUrl"

    if ($currentVersion -and $currentVersion -ge $latestVersion) {
        Write-Host "7-Zip is already up to date. No update needed."
        exit 0
    }

    Write-Host "Downloading 7-Zip installer..."
    Invoke-WebRequest `
        -Uri $downloadUrl `
        -OutFile $installerPath `
        -Headers @{
            "Cache-Control" = "no-cache"
            "Pragma"        = "no-cache"
        }

    if (-not (Test-Path $installerPath)) {
        Write-Host "Installer was not downloaded. Aborting."
        exit 1
    }

    $installerSize = (Get-Item $installerPath).Length

    if ($installerSize -lt 500KB) {
        Write-Host "Downloaded file is too small. It is probably not a valid installer."
        Write-Host "File size: $installerSize bytes"
        exit 1
    }

    Write-Host "Installing 7-Zip silently..."
    $process = Start-Process `
        -FilePath $installerPath `
        -ArgumentList "/S" `
        -Wait `
        -PassThru

    if ($process.ExitCode -ne 0) {
        Write-Host "7-Zip installer exited with code $($process.ExitCode)."
        exit $process.ExitCode
    }

    Start-Sleep -Seconds 2

    $newVersion = Get-7ZipVersion
    $newExePath = Get-7ZipExePath

    if (-not $newVersion) {
        Write-Host "Could not detect the installed 7-Zip version after installation."
        exit 1
    }

    Write-Host "New 7-Zip version: $newVersion"
    Write-Host "New 7-Zip path: $newExePath"

    if ($newVersion -ge $latestVersion) {
        Write-Host "7-Zip successfully installed or updated to version $newVersion."
        exit 0
    }

    Write-Host "7-Zip installation completed, but detected version is lower than expected."
    Write-Host "Expected: $latestVersion"
    Write-Host "Detected: $newVersion"
    exit 1
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
