
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

$scriptUrl = "https://raw.githubusercontent.com/Gustxxl/7zUpdater/refs/heads/main/7zUpdater.ps1"
$githubApiUrl = "https://api.github.com/repos/ip7z/7zip/releases/latest"
$installerPath = Join-Path $env:TEMP "7zip-installer.exe"

function Write-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

function Exit-Script {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Code
    )

    Write-Host ""
    Write-Host "========================================"
    Write-Host "Script finished with code $Code."
    Write-Host "========================================"

    $global:LASTEXITCODE = $Code
    exit $Code
}

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-Elevated {
    Write-Step "Restarting script as Administrator..."

    $elevatedCommand = "irm '$scriptUrl' | iex"

    $process = Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$elevatedCommand`"" `
        -Verb RunAs `
        -PassThru

    if (-not $process) {
        throw "Failed to relaunch PowerShell with elevation."
    }

    exit 0
}

function Get-FileVersionSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop

        $candidates = @(
            $item.VersionInfo.ProductVersion,
            $item.VersionInfo.FileVersion
        )

        foreach ($candidate in $candidates) {
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                $normalized = ($candidate -split '\s+')[0].Trim()

                try {
                    return [version]$normalized
                }
                catch {
                }
            }
        }

        return $null
    }
    catch {
        return $null
    }
}

function Get-Installed7ZipFiles {
    $preferredPaths = @(
        "C:\Program Files\7-Zip\7zFM.exe",
        "C:\Program Files\7-Zip\7z.exe",
        "C:\Program Files (x86)\7-Zip\7zFM.exe",
        "C:\Program Files (x86)\7-Zip\7z.exe"
    )

    $items = @()

    foreach ($path in $preferredPaths) {
        if (Test-Path -LiteralPath $path) {
            $file = Get-Item -LiteralPath $path -ErrorAction Stop

            $items += [PSCustomObject]@{
                Path          = $file.FullName
                Name          = $file.Name
                Version       = Get-FileVersionSafe -Path $file.FullName
                LastWriteTime = $file.LastWriteTime
                Length        = $file.Length
            }
        }
    }

    return @($items)
}

function Show-Installed7ZipFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    Write-Step $Title

    $files = @(Get-Installed7ZipFiles)

    if ($files.Count -eq 0) {
        Write-Step "No 7-Zip files found in standard installation paths."
        return
    }

    foreach ($item in $files) {
        Write-Host ""
        Write-Host "Path:          $($item.Path)"
        Write-Host "Version:       $($item.Version)"
        Write-Host "LastWriteTime: $($item.LastWriteTime)"
        Write-Host "Size:          $($item.Length) bytes"
    }

    Write-Host ""
}

function Stop-7ZipProcesses {
    Write-Step "Stopping running 7-Zip processes if any..."

    $targetNames = @("7z", "7zFM", "7zG")
    $processes = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -in $targetNames
    })

    if ($processes.Count -eq 0) {
        Write-Step "No running 7-Zip processes detected."
        return
    }

    foreach ($process in $processes) {
        try {
            Write-Step "Stopping process $($process.ProcessName) (PID $($process.Id))"
            Stop-Process -Id $process.Id -Force -ErrorAction Stop
        }
        catch {
            Write-Step "Could not stop process $($process.ProcessName) (PID $($process.Id)): $($_.Exception.Message)"
        }
    }

    Start-Sleep -Seconds 2

    $leftovers = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -in $targetNames
    })

    if ($leftovers.Count -gt 0) {
        $leftoverText = ($leftovers | ForEach-Object { "$($_.ProcessName)#$($_.Id)" }) -join ", "
        throw "Some 7-Zip processes are still running: $leftoverText"
    }

    Write-Step "All 7-Zip processes stopped."
}

function Get-Latest7ZipRelease {
    $response = Invoke-RestMethod `
        -Uri $githubApiUrl `
        -Headers @{
            "Accept" = "application/vnd.github+json"
            "User-Agent" = "7zUpdater"
            "Cache-Control" = "no-cache"
            "Pragma" = "no-cache"
        } `
        -ErrorAction Stop

    if (-not $response) {
        throw "Empty response from GitHub API."
    }

    if (-not $response.tag_name) {
        throw "Could not detect latest release tag from GitHub."
    }

    $versionText = $response.tag_name.TrimStart("v").Trim()

    try {
        $version = [version]$versionText
    }
    catch {
        throw "Invalid release version format from GitHub: $versionText"
    }

    $asset = $response.assets | Where-Object {
        $_.name -match '^7z\d{4,}-x64\.exe$' -and $_.browser_download_url
    } | Select-Object -First 1

    if (-not $asset) {
        throw "Could not find x64 installer asset in latest GitHub release."
    }

    return [PSCustomObject]@{
        Version     = $version
        AssetName   = $asset.name
        DownloadUrl = $asset.browser_download_url
    }
}

function Get-PrimaryInstalledManagerPath {
    return "C:\Program Files\7-Zip\7zFM.exe"
}

function Get-PrimaryInstalledCliPath {
    return "C:\Program Files\7-Zip\7z.exe"
}

try {
    if (-not (Test-IsAdministrator)) {
        Restart-Elevated
    }

    Write-Step "7-Zip updater started."
    Write-Step "Running as Administrator: $(Test-IsAdministrator)"
    Write-Step "PowerShell version: $($PSVersionTable.PSVersion)"

    Show-Installed7ZipFiles -Title "Detected 7-Zip files before update:"

    Stop-7ZipProcesses

    $latest = Get-Latest7ZipRelease

    Write-Step "Latest official version detected: $($latest.Version)"
    Write-Step "Installer asset: $($latest.AssetName)"
    Write-Step "Installer URL: $($latest.DownloadUrl)"

    $managerPath = Get-PrimaryInstalledManagerPath
    $cliPath = Get-PrimaryInstalledCliPath

    $currentManagerVersion = Get-FileVersionSafe -Path $managerPath
    $currentCliVersion = Get-FileVersionSafe -Path $cliPath

    Write-Step "Primary manager path: $managerPath"
    Write-Step "Primary manager version: $currentManagerVersion"
    Write-Step "Primary CLI path: $cliPath"
    Write-Step "Primary CLI version: $currentCliVersion"

    if ($currentManagerVersion -and $currentManagerVersion -ge $latest.Version) {
        Write-Step "7-Zip is already up to date."
        Exit-Script -Code 0
    }

    if (Test-Path -LiteralPath $installerPath) {
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    }

    Write-Step "Downloading installer..."
    Invoke-WebRequest `
        -Uri $latest.DownloadUrl `
        -OutFile $installerPath `
        -Headers @{
            "User-Agent" = "7zUpdater"
            "Cache-Control" = "no-cache"
            "Pragma" = "no-cache"
        } `
        -ErrorAction Stop

    if (-not (Test-Path -LiteralPath $installerPath)) {
        throw "Installer was not downloaded."
    }

    $installerFile = Get-Item -LiteralPath $installerPath -ErrorAction Stop
    Write-Step "Downloaded installer path: $installerPath"
    Write-Step "Downloaded installer size: $($installerFile.Length) bytes"

    if ($installerFile.Length -lt 500KB) {
        throw "Downloaded file is too small. Probably not a valid installer."
    }

    Stop-7ZipProcesses

    Write-Step "Starting silent installation..."
    $process = Start-Process `
        -FilePath $installerPath `
        -ArgumentList "/S" `
        -Wait `
        -PassThru `
        -WindowStyle Hidden `
        -ErrorAction Stop

    Write-Step "Installer process exited."
    Write-Step "Installer exit code: $($process.ExitCode)"

    if ($process.ExitCode -ne 0) {
        throw "7-Zip installer failed with exit code $($process.ExitCode)."
    }

    Start-Sleep -Seconds 3

    $newManagerVersion = Get-FileVersionSafe -Path $managerPath
    $newCliVersion = Get-FileVersionSafe -Path $cliPath

    Show-Installed7ZipFiles -Title "Detected 7-Zip files after update:"

    Write-Step "Detected manager version after install: $newManagerVersion"
    Write-Step "Detected CLI version after install: $newCliVersion"

    if ($newManagerVersion -and $newManagerVersion -ge $latest.Version) {
        Write-Step "SUCCESS: 7-Zip successfully installed or updated to version $newManagerVersion."
        Exit-Script -Code 0
    }

    throw "Installer completed, but expected version was not detected in $managerPath."
}
catch {
    Write-Step "ERROR: $($_.Exception.Message)"
    Exit-Script -Code 1
}
finally {
    if (Test-Path -LiteralPath $installerPath) {
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    }
}
