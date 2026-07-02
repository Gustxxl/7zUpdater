
$ErrorActionPreference = "Stop"

$scriptUrl = "https://raw.githubusercontent.com/Gustxxl/7zUpdater/refs/heads/main/7zUpdater.ps1"

$downloadPageUrl = "https://www.7-zip.org/download.html"
$installerPath = Join-Path $env:TEMP "7zip-installer.exe"
$logPath = Join-Path $env:TEMP "7zip-updater.log"

$knownSevenZipExePaths = @(
    "C:\Program Files\7-Zip\7z.exe",
    "C:\Program Files\7-Zip\7zFM.exe",
    "C:\Program Files (x86)\7-Zip\7z.exe",
    "C:\Program Files (x86)\7-Zip\7zFM.exe"
)

function Write-Step {
    param (
        [Parameter(Mandatory)]
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-IsInteractiveSession {
    try {
        return [Environment]::UserInteractive
    }
    catch {
        return $true
    }
}

function Complete-Script {
    param (
        [Parameter(Mandatory)]
        [int]$Code
    )

    Write-Host ""
    Write-Host "========================================"

    if ($Code -eq 0) {
        Write-Host "7-Zip updater finished successfully."
    } else {
        Write-Host "7-Zip updater finished with errors."
    }

    Write-Host "Exit code: $Code"
    Write-Host "Log file: $logPath"
    Write-Host "========================================"

    if (Test-IsInteractiveSession) {
        Write-Host "Press Enter to close this window..."
        Read-Host | Out-Null
    }

    $global:LASTEXITCODE = $Code
    return
}

if (-not (Test-IsAdministrator)) {
    Write-Step "Restarting script as Administrator..."

    $elevatedCommand = "irm '$scriptUrl' | iex"

    Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -Command `"$elevatedCommand`"" `
        -Verb RunAs

    exit 0
}

function Get-7ZipVersionFromExe {
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    try {
        $file = Get-Item $Path

        $productVersion = $file.VersionInfo.ProductVersion
        if ($productVersion -match "(\d+\.\d+)") {
            return [version]$matches[1]
        }

        $fileVersion = $file.VersionInfo.FileVersion
        if ($fileVersion -match "(\d+\.\d+)") {
            return [version]$matches[1]
        }

        if ((Split-Path $Path -Leaf) -ieq "7z.exe") {
            $versionOutput = (& $Path) -join "`n"

            $match = [regex]::Match($versionOutput, "7-Zip\s+(\d+\.\d+)")
            if ($match.Success) {
                return [version]$match.Groups[1].Value
            }
        }

        return $null
    }
    catch {
        return $null
    }
}

function Get-Existing7ZipInstallations {
    $items = @()

    foreach ($path in $knownSevenZipExePaths) {
        if (Test-Path $path) {
            $resolvedPath = (Resolve-Path $path).Path

            if ($items.Path -contains $resolvedPath) {
                continue
            }

            $file = Get-Item $resolvedPath
            $version = Get-7ZipVersionFromExe -Path $resolvedPath

            $items += [PSCustomObject]@{
                Path          = $resolvedPath
                Version       = $version
                LastWriteTime = $file.LastWriteTime
                Length        = $file.Length
                Source        = "KnownPath"
            }
        }
    }

    $commands = @()

    $commands += @(Get-Command "7z.exe" -ErrorAction SilentlyContinue)
    $commands += @(Get-Command "7zFM.exe" -ErrorAction SilentlyContinue)

    foreach ($command in $commands) {
        if (-not $command) {
            continue
        }

        if (-not $command.Source) {
            continue
        }

        if (-not (Test-Path $command.Source)) {
            continue
        }

        $resolvedPath = (Resolve-Path $command.Source).Path

        if ($items.Path -contains $resolvedPath) {
            continue
        }

        $file = Get-Item $resolvedPath
        $version = Get-7ZipVersionFromExe -Path $resolvedPath

        $items += [PSCustomObject]@{
            Path          = $resolvedPath
            Version       = $version
            LastWriteTime = $file.LastWriteTime
            Length        = $file.Length
            Source        = "PATH"
        }
    }

    return $items
}

function Convert-VersionToInstallerNumber {
    param (
        [Parameter(Mandatory)]
        [version]$Version
    )

    return "{0}{1:D2}" -f $Version.Major, $Version.Minor
}

function Show-7ZipInstallations {
    param (
        [Parameter(Mandatory)]
        [string]$Title
    )

    Write-Step $Title

    $installations = @(Get-Existing7ZipInstallations)

    if ($installations.Count -eq 0) {
        Write-Step "No 7-Zip installations found in known paths or PATH."
        return
    }

    foreach ($item in $installations) {
        Write-Host ""
        Write-Host "Path:          $($item.Path)"
        Write-Host "Version:       $($item.Version)"
        Write-Host "LastWriteTime: $($item.LastWriteTime)"
        Write-Host "Size:          $($item.Length) bytes"
        Write-Host "Source:        $($item.Source)"
    }

    Write-Host ""
}

function Get-Latest7ZipVersion {
    Write-Step "Fetching official 7-Zip download page: $downloadPageUrl"

    $downloadPageContent = Invoke-WebRequest `
        -Uri $downloadPageUrl `
        -UseBasicParsing `
        -Headers @{
            "Cache-Control" = "no-cache"
            "Pragma"        = "no-cache"
            "User-Agent"    = "Mozilla/5.0 Windows PowerShell 7-Zip Updater"
        }

    $html = $downloadPageContent.Content

    $latestVersionMatch = [regex]::Match(
        $html,
        "Download\s+7-Zip\s+(\d+\.\d+)",
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if (-not $latestVersionMatch.Success) {
        throw "Could not detect the latest 7-Zip version from the official page."
    }

    return [version]$latestVersionMatch.Groups[1].Value
}

function Get-HighestInstalled7ZipVersion {
    $installations = @(Get-Existing7ZipInstallations)

    if ($installations.Count -eq 0) {
        return $null
    }

    $bestInstallation = $installations |
        Where-Object { $_.Version -ne $null } |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $bestInstallation) {
        return $null
    }

    return $bestInstallation.Version
}

function Stop-7ZipProcesses {
    $runningProcesses = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -in @("7z", "7zFM", "7zG")
    })

    if ($runningProcesses.Count -eq 0) {
        Write-Step "No running 7-Zip processes detected."
        return
    }

    Write-Step "Detected running 7-Zip processes. Stopping them..."

    foreach ($process in $runningProcesses) {
        Write-Host "Process: $($process.ProcessName), PID: $($process.Id)"
    }

    $runningProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Remove-InstallerIfExists {
    if (Test-Path $installerPath) {
        Write-Step "Removing old installer from temp: $installerPath"
        Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    }
}

try {
    Start-Transcript -Path $logPath -Force | Out-Null

    Write-Step "7-Zip updater started."
    Write-Step "Log file: $logPath"
    Write-Step "Running as Administrator: $(Test-IsAdministrator)"
    Write-Step "PowerShell version: $($PSVersionTable.PSVersion)"
    Write-Step "Script URL: $scriptUrl"

    Show-7ZipInstallations -Title "Detected 7-Zip installations before update:"

    Stop-7ZipProcesses

    $latestVersion = Get-Latest7ZipVersion
    $installerVersionNumber = Convert-VersionToInstallerNumber -Version $latestVersion
    $downloadUrl = "https://www.7-zip.org/a/7z$installerVersionNumber-x64.exe"

    Write-Step "Latest official version detected: $latestVersion"
    Write-Step "Installer version number: $installerVersionNumber"
    Write-Step "Installer URL: $downloadUrl"

    $currentVersion = Get-HighestInstalled7ZipVersion

    if ($currentVersion) {
        Write-Step "Highest currently detected 7-Zip version: $currentVersion"
    } else {
        Write-Step "No current 7-Zip version detected."
    }

    if ($currentVersion -and $currentVersion -ge $latestVersion) {
        Write-Step "7-Zip is already up to date. No update needed."
        Complete-Script -Code 0
        return
    }

    Remove-InstallerIfExists

    Write-Step "Downloading installer..."

    Invoke-WebRequest `
        -Uri $downloadUrl `
        -OutFile $installerPath `
        -Headers @{
            "Cache-Control" = "no-cache"
            "Pragma"        = "no-cache"
            "User-Agent"    = "Mozilla/5.0 Windows PowerShell 7-Zip Updater"
        }

    if (-not (Test-Path $installerPath)) {
        throw "Installer was not downloaded."
    }

    $installerFile = Get-Item $installerPath

    Write-Step "Downloaded installer path: $installerPath"
    Write-Step "Downloaded installer size: $($installerFile.Length) bytes"
    Write-Step "Downloaded installer last write time: $($installerFile.LastWriteTime)"

    if ($installerFile.Length -lt 500KB) {
        throw "Downloaded file is too small. Probably not a valid installer."
    }

    $installerHash = Get-FileHash -Path $installerPath -Algorithm SHA256
    Write-Step "Downloaded installer SHA256: $($installerHash.Hash)"

    Write-Step "Starting silent installation..."
    Write-Step "Command: `"$installerPath`" /S"

    $process = Start-Process `
        -FilePath $installerPath `
        -ArgumentList "/S" `
        -Wait `
        -PassThru

    Write-Step "Installer process exited."
    Write-Step "Installer exit code: $($process.ExitCode)"

    if ($process.ExitCode -ne 0) {
        throw "7-Zip installer failed with exit code $($process.ExitCode)."
    }

    Write-Step "Waiting after installation..."
    Start-Sleep -Seconds 5

    Show-7ZipInstallations -Title "Detected 7-Zip installations after update:"

    $newVersion = Get-HighestInstalled7ZipVersion

    if (-not $newVersion) {
        throw "Could not detect 7-Zip after installation."
    }

    Write-Step "Highest detected version after installation: $newVersion"

    if ($newVersion -ge $latestVersion) {
        Write-Step "SUCCESS: 7-Zip successfully installed or updated to version $newVersion."
        Complete-Script -Code 0
        return
    }

    Write-Step "WARNING: Installer finished successfully, but detected version is still lower than expected."
    Write-Step "Expected version: $latestVersion"
    Write-Step "Detected version: $newVersion"
    Write-Step "Possible causes:"
    Write-Step "1. Another old 7-Zip installation exists and is being detected."
    Write-Step "2. 7-Zip was installed into a non-standard directory."
    Write-Step "3. The installer did not overwrite the existing installation."
    Write-Step "4. Security software blocked file replacement."
    Write-Step "5. The opened 7-Zip File Manager belongs to another installation path."

    Complete-Script -Code 1
    return
}
catch {
    Write-Step "ERROR: $($_.Exception.Message)"
    Complete-Script -Code 1
    return
}
finally {
    Remove-InstallerIfExists

    try {
        Stop-Transcript | Out-Null
    }
    catch {
    }

    Write-Host ""
    Write-Host "Log saved to:"
    Write-Host $logPath
}
