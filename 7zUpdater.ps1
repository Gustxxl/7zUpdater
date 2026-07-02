
$ErrorActionPreference = "Stop"

$scriptUrl = "https://raw.githubusercontent.com/Gustxxl/7zUpdater/refs/heads/main/7zUpdater.ps1"

$downloadPageUrl = "https://www.7-zip.org/download.html"
$installerPath = Join-Path $env:TEMP "7zip-installer.exe"
$logPath = Join-Path $env:TEMP "7zip-updater.log"

$standardSevenZipPaths = @(
    "C:\Program Files\7-Zip\7z.exe",
    "C:\Program Files (x86)\7-Zip\7z.exe"
)

function Wait-BeforeExit {
    Write-Host ""
    Write-Host "========================================"
    Write-Host "Script finished. Press Enter to close..."
    Write-Host "Log file: $logPath"
    Write-Host "========================================"
    Read-Host | Out-Null
}

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

if (-not (Test-IsAdministrator)) {
    Write-Step "Restarting script as Administrator..."

    $elevatedCommand = "irm '$scriptUrl' | iex"

    Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -Command `"$elevatedCommand`"" `
        -Verb RunAs

    exit 0
}

function Exit-WithPause {
    param (
        [Parameter(Mandatory)]
        [int]$Code
    )

    Wait-BeforeExit
    exit $Code
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
        $versionOutput = (& $Path) -join "`n"

        $match = [regex]::Match($versionOutput, "7-Zip\s+(\d+\.\d+)")
        if ($match.Success) {
            return [version]$match.Groups[1].Value
        }

        return $null
    }
    catch {
        return $null
    }
}

function Get-Existing7ZipInstallations {
    $items = @()

    foreach ($path in $standardSevenZipPaths) {
        if (Test-Path $path) {
            $file = Get-Item $path
            $version = Get-7ZipVersionFromExe -Path $path

            $items += [PSCustomObject]@{
                Path          = $path
                Version       = $version
                LastWriteTime = $file.LastWriteTime
                Length        = $file.Length
                Source        = "StandardPath"
            }
        }
    }

    $pathResults = @(where.exe 7z 2>$null)

    foreach ($path in $pathResults) {
        if ($path -and (Test-Path $path)) {
            $resolvedPath = (Resolve-Path $path).Path

            if (-not ($items.Path -contains $resolvedPath)) {
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
        Write-Step "No 7-Zip installations found in standard paths or PATH."
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

try {
    Start-Transcript -Path $logPath -Force | Out-Null

    Write-Step "7-Zip updater started."
    Write-Step "Log file: $logPath"
    Write-Step "Running as Administrator: $(Test-IsAdministrator)"
    Write-Step "PowerShell version: $($PSVersionTable.PSVersion)"
    Write-Step "Process architecture: $([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture)"
    Write-Step "OS architecture: $([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)"

    Show-7ZipInstallations -Title "Detected 7-Zip installations before update:"

    $runningProcesses = @(Get-Process | Where-Object {
        $_.ProcessName -in @("7z", "7zFM", "7zG")
    })

    if ($runningProcesses.Count -gt 0) {
        Write-Step "Detected running 7-Zip processes. Stopping them..."

        foreach ($process in $runningProcesses) {
            Write-Host "Process: $($process.ProcessName), PID: $($process.Id)"
        }

        $runningProcesses | Stop-Process -Force
        Start-Sleep -Seconds 2
    } else {
        Write-Step "No running 7-Zip processes detected."
    }

    Write-Step "Fetching official 7-Zip download page: $downloadPageUrl"

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
        throw "Could not detect the latest 7-Zip version from the official page."
    }

    $latestVersion = [version]$latestVersionMatch.Groups[1].Value
    $installerVersionNumber = Convert-VersionToInstallerNumber -Version $latestVersion
    $downloadUrl = "https://www.7-zip.org/a/7z$installerVersionNumber-x64.exe"

    Write-Step "Latest official version detected: $latestVersion"
    Write-Step "Installer version number: $installerVersionNumber"
    Write-Step "Installer URL: $downloadUrl"

    $currentInstallations = @(Get-Existing7ZipInstallations)
    $bestCurrentVersion = $null

    if ($currentInstallations.Count -gt 0) {
        $bestCurrentVersion = $currentInstallations |
            Where-Object { $_.Version -ne $null } |
            Sort-Object Version -Descending |
            Select-Object -First 1 -ExpandProperty Version
    }

    if ($bestCurrentVersion) {
        Write-Step "Highest currently detected 7-Zip version: $bestCurrentVersion"
    } else {
        Write-Step "No current 7-Zip version detected."
    }

    if ($bestCurrentVersion -and $bestCurrentVersion -ge $latestVersion) {
        Write-Step "7-Zip is already up to date. No update needed."
        Exit-WithPause -Code 0
    }

    if (Test-Path $installerPath) {
        Write-Step "Removing old installer from temp: $installerPath"
        Remove-Item -Path $installerPath -Force
    }

    Write-Step "Downloading installer..."
    Invoke-WebRequest `
        -Uri $downloadUrl `
        -OutFile $installerPath `
        -Headers @{
            "Cache-Control" = "no-cache"
            "Pragma"        = "no-cache"
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

    $newInstallations = @(Get-Existing7ZipInstallations)

    $bestNewInstallation = $newInstallations |
        Where-Object { $_.Version -ne $null } |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $bestNewInstallation) {
        throw "Could not detect 7-Zip after installation."
    }

    Write-Step "Highest detected version after installation: $($bestNewInstallation.Version)"
    Write-Step "Highest detected version path: $($bestNewInstallation.Path)"

    if ($bestNewInstallation.Version -ge $latestVersion) {
        Write-Step "SUCCESS: 7-Zip successfully installed or updated to version $($bestNewInstallation.Version)."
        Exit-WithPause -Code 0
    }

    Write-Step "WARNING: Installer finished successfully, but detected version is still lower than expected."
    Write-Step "Expected version: $latestVersion"
    Write-Step "Detected version: $($bestNewInstallation.Version)"

    Exit-WithPause -Code 1
}
catch {
    Write-Step "ERROR: $($_.Exception.Message)"
    Exit-WithPause -Code 1
}
finally {
    if (Test-Path $installerPath) {
        Write-Step "Cleaning up installer file: $installerPath"
        Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    }

    try {
        Stop-Transcript | Out-Null
    }
    catch {
    }
}
