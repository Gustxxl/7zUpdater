
$ErrorActionPreference = "Stop"

$scriptUrl = "https://raw.githubusercontent.com/Gustxxl/7zUpdater/refs/heads/main/7zUpdater.ps1"
$githubApiUrl = "https://api.github.com/repos/ip7z/7zip/releases/latest"
$installerPath = Join-Path $env:TEMP "7zip-installer.exe"

function Write-Step {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

function Complete-Script {
    param(
        [Parameter(Mandatory)]
        [int]$Code
    )

    Write-Host ""
    Write-Host "========================================"
    Write-Host "Script finished with code $Code."
    Write-Host "Press Enter to close this window..."
    Write-Host "========================================"
    Read-Host | Out-Null

    $global:LASTEXITCODE = $Code
    return
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

function Get-7ZipVersionFromExe {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    try {
        $versionOutput = & $Path 2>$null | Out-String

        $match = [regex]::Match($versionOutput, "7-Zip\s+(\d+\.\d+)")
        if ($match.Success) {
            return [version]$match.Groups[1].Value
        }

        $item = Get-Item $Path -ErrorAction Stop
        if ($item.VersionInfo -and $item.VersionInfo.ProductVersion) {
            $productVersion = $item.VersionInfo.ProductVersion.Split(" ")[0]
            try {
                return [version]$productVersion
            }
            catch {
            }
        }

        return $null
    }
    catch {
        return $null
    }
}

function Get-CommandPaths {
    param(
        [Parameter(Mandatory)]
        [string[]]$Names
    )

    $results = @()

    foreach ($name in $Names) {
        try {
            $cmds = @(Get-Command $name -ErrorAction SilentlyContinue)
            foreach ($cmd in $cmds) {
                if ($cmd.CommandType -eq "Application" -and $cmd.Source) {
                    $results += $cmd.Source
                }
            }
        }
        catch {
        }
    }

    return $results | Sort-Object -Unique
}

function Get-UninstallRegistryInstallations {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $items = @()

    foreach ($regPath in $paths) {
        try {
            $entries = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            foreach ($entry in $entries) {
                if ($entry.DisplayName -like "7-Zip*") {
                    $installLocation = $entry.InstallLocation
                    if ($installLocation) {
                        $exePath = Join-Path $installLocation "7z.exe"
                        if (Test-Path $exePath) {
                            $items += $exePath
                        }
                    }
                }
            }
        }
        catch {
        }
    }

    return $items | Sort-Object -Unique
}

function Get-Existing7ZipInstallations {
    $candidatePaths = @(
        "C:\Program Files\7-Zip\7z.exe",
        "C:\Program Files\7-Zip\7zFM.exe",
        "C:\Program Files (x86)\7-Zip\7z.exe",
        "C:\Program Files (x86)\7-Zip\7zFM.exe"
    )

    $candidatePaths += Get-CommandPaths -Names @("7z", "7zFM")
    $candidatePaths += Get-UninstallRegistryInstallations

    $candidatePaths = $candidatePaths | Sort-Object -Unique

    $items = @()

    foreach ($path in $candidatePaths) {
        if (Test-Path $path) {
            try {
                $file = Get-Item $path -ErrorAction Stop
                $version = Get-7ZipVersionFromExe -Path $path

                $items += [PSCustomObject]@{
                    Path          = $file.FullName
                    Version       = $version
                    LastWriteTime = $file.LastWriteTime
                    Length        = $file.Length
                }
            }
            catch {
            }
        }
    }

    $items |
        Sort-Object Path -Unique
}

function Show-7ZipInstallations {
    param(
        [Parameter(Mandatory)]
        [string]$Title
    )

    Write-Step $Title

    $installations = @(Get-Existing7ZipInstallations)

    if ($installations.Count -eq 0) {
        Write-Step "No 7-Zip installations found."
        return
    }

    foreach ($item in $installations) {
        Write-Host ""
        Write-Host "Path:          $($item.Path)"
        Write-Host "Version:       $($item.Version)"
        Write-Host "LastWriteTime: $($item.LastWriteTime)"
        Write-Host "Size:          $($item.Length) bytes"
    }

    Write-Host ""
}

function Get-Latest7ZipRelease {
    $response = Invoke-RestMethod `
        -Uri $githubApiUrl `
        -Headers @{
            "Accept" = "application/vnd.github+json"
            "User-Agent" = "7zUpdater"
            "Cache-Control" = "no-cache"
            "Pragma" = "no-cache"
        }

    if (-not $response.tag_name) {
        throw "Could not detect latest release tag from GitHub."
    }

    $versionText = $response.tag_name.TrimStart("v")
    $version = [version]$versionText

    $asset = $response.assets | Where-Object {
        $_.name -match '^7z\d{4,}-x64\.exe$'
    } | Select-Object -First 1

    if (-not $asset) {
        throw "Could not find x64 installer asset in latest GitHub release."
    }

    [PSCustomObject]@{
        Version = $version
        DownloadUrl = $asset.browser_download_url
        AssetName = $asset.name
    }
}

try {
    Write-Step "7-Zip updater started."
    Write-Step "Running as Administrator: $(Test-IsAdministrator)"
    Write-Step "PowerShell version: $($PSVersionTable.PSVersion)"

    Show-7ZipInstallations -Title "Detected 7-Zip installations before update:"

    $runningProcesses = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -in @("7z", "7zFM", "7zG")
    })

    if ($runningProcesses.Count -gt 0) {
        Write-Step "Detected running 7-Zip processes. Stopping them..."

        foreach ($process in $runningProcesses) {
            Write-Host "Process: $($process.ProcessName), PID: $($process.Id)"
        }

        $runningProcesses | Stop-Process -Force
        Start-Sleep -Seconds 2
    }
    else {
        Write-Step "No running 7-Zip processes detected."
    }

    $latest = Get-Latest7ZipRelease

    Write-Step "Latest official version detected: $($latest.Version)"
    Write-Step "Installer asset: $($latest.AssetName)"
    Write-Step "Installer URL: $($latest.DownloadUrl)"

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
    }
    else {
        Write-Step "No current 7-Zip version detected."
    }

    if ($bestCurrentVersion -and $bestCurrentVersion -ge $latest.Version) {
        Write-Step "7-Zip is already up to date. No update needed."
        Complete-Script -Code 0
        return
    }

    if (Test-Path $installerPath) {
        Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    }

    Write-Step "Downloading installer..."
    Invoke-WebRequest `
        -Uri $latest.DownloadUrl `
        -OutFile $installerPath `
        -Headers @{
            "User-Agent" = "7zUpdater"
            "Cache-Control" = "no-cache"
            "Pragma" = "no-cache"
        }

    if (-not (Test-Path $installerPath)) {
        throw "Installer was not downloaded."
    }

    $installerFile = Get-Item $installerPath -ErrorAction Stop
    Write-Step "Downloaded installer path: $installerPath"
    Write-Step "Downloaded installer size: $($installerFile.Length) bytes"

    if ($installerFile.Length -lt 500KB) {
        throw "Downloaded file is too small. Probably not a valid installer."
    }

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

    if ($bestNewInstallation.Version -ge $latest.Version) {
        Write-Step "SUCCESS: 7-Zip successfully installed or updated to version $($bestNewInstallation.Version)."
        Complete-Script -Code 0
        return
    }

    throw "Installer completed, but detected version is still lower than expected. Installed path may differ from the detected executable."
}
catch {
    Write-Step "ERROR: $($_.Exception.Message)"
    Complete-Script -Code 1
    return
}
finally {
    if (Test-Path $installerPath) {
        Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    }
}
