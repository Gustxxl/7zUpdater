
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

function Get-FileVersionSafe {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    try {
        $item = Get-Item $Path -ErrorAction Stop

        if ($item.VersionInfo -and $item.VersionInfo.ProductVersion) {
            $raw = ($item.VersionInfo.ProductVersion -split '\s+')[0]
            try {
                return [version]$raw
            }
            catch {
            }
        }

        if ($item.VersionInfo -and $item.VersionInfo.FileVersion) {
            $raw = ($item.VersionInfo.FileVersion -split '\s+')[0]
            try {
                return [version]$raw
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

    $results = New-Object System.Collections.Generic.List[string]

    foreach ($name in $Names) {
        try {
            $cmds = @(Get-Command $name -ErrorAction SilentlyContinue)
            foreach ($cmd in $cmds) {
                if ($cmd.CommandType -eq "Application" -and $cmd.Source) {
                    [void]$results.Add($cmd.Source)
                }
            }
        }
        catch {
        }
    }

    return @($results | Sort-Object -Unique)
}

function Get-UninstallRegistryCandidates {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $paths = New-Object System.Collections.Generic.List[string]

    foreach ($regPath in $regPaths) {
        try {
            $entries = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            foreach ($entry in $entries) {
                if ($entry.DisplayName -like "7-Zip*") {
                    if ($entry.InstallLocation) {
                        $fm = Join-Path $entry.InstallLocation "7zFM.exe"
                        $cli = Join-Path $entry.InstallLocation "7z.exe"

                        if (Test-Path $fm) {
                            [void]$paths.Add($fm)
                        }
                        if (Test-Path $cli) {
                            [void]$paths.Add($cli)
                        }
                    }
                }
            }
        }
        catch {
        }
    }

    return @($paths | Sort-Object -Unique)
}

function Get-Existing7ZipInstallations {
    $candidatePaths = @(
        "C:\Program Files\7-Zip\7zFM.exe",
        "C:\Program Files\7-Zip\7z.exe",
        "C:\Program Files (x86)\7-Zip\7zFM.exe",
        "C:\Program Files (x86)\7-Zip\7z.exe"
    )

    $candidatePaths += Get-CommandPaths -Names @("7z", "7zFM")
    $candidatePaths += Get-UninstallRegistryCandidates
    $candidatePaths = $candidatePaths | Sort-Object -Unique

    $items = @()

    foreach ($path in $candidatePaths) {
        if (Test-Path $path) {
            try {
                $file = Get-Item $path -ErrorAction Stop
                $version = Get-FileVersionSafe -Path $file.FullName

                $kind = if ($file.Name -ieq "7zFM.exe") { "Manager" } else { "CLI" }
                $arch = if ($file.FullName -like "C:\Program Files (x86)\*") { "x86" } else { "x64/unknown" }
                $priority = switch -Regex ($file.FullName) {
                    '^C:\\Program Files\\7-Zip\\7zFM\.exe$' { 100; break }
                    '^C:\\Program Files\\7-Zip\\7z\.exe$'   { 90; break }
                    '^C:\\Program Files \(x86\)\\7-Zip\\7zFM\.exe$' { 80; break }
                    '^C:\\Program Files \(x86\)\\7-Zip\\7z\.exe$'   { 70; break }
                    default { 10; break }
                }

                $items += [PSCustomObject]@{
                    Path          = $file.FullName
                    Name          = $file.Name
                    Kind          = $kind
                    Arch          = $arch
                    Version       = $version
                    LastWriteTime = $file.LastWriteTime
                    Length        = $file.Length
                    Priority      = $priority
                }
            }
            catch {
            }
        }
    }

    return @($items | Sort-Object Path -Unique)
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

    foreach ($item in $installations | Sort-Object Priority -Descending, Version -Descending, Path) {
        Write-Host ""
        Write-Host "Path:          $($item.Path)"
        Write-Host "Name:          $($item.Name)"
        Write-Host "Kind:          $($item.Kind)"
        Write-Host "Arch:          $($item.Arch)"
        Write-Host "Version:       $($item.Version)"
        Write-Host "LastWriteTime: $($item.LastWriteTime)"
        Write-Host "Size:          $($item.Length) bytes"
        Write-Host "Priority:      $($item.Priority)"
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

function Get-PreferredManager {
    $installations = @(Get-Existing7ZipInstallations)

    $preferred = $installations |
        Where-Object { $_.Name -ieq "7zFM.exe" } |
        Sort-Object Priority -Descending, Version -Descending |
        Select-Object -First 1

    return $preferred
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

    $currentPreferredManager = Get-PreferredManager

    if ($currentPreferredManager) {
        Write-Step "Preferred current manager: $($currentPreferredManager.Path)"
        Write-Step "Preferred current manager version: $($currentPreferredManager.Version)"
    }
    else {
        Write-Step "No current 7-Zip Manager detected."
    }

    if ($currentPreferredManager -and $currentPreferredManager.Version -and $currentPreferredManager.Version -ge $latest.Version) {
        Write-Step "7-Zip Manager is already up to date."
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

    $programFilesManager = "C:\Program Files\7-Zip\7zFM.exe"
    $programFilesCli = "C:\Program Files\7-Zip\7z.exe"

    $managerVersion = if (Test-Path $programFilesManager) { Get-FileVersionSafe -Path $programFilesManager } else { $null }
    $cliVersion = if (Test-Path $programFilesCli) { Get-FileVersionSafe -Path $programFilesCli } else { $null }

    Write-Step "Primary manager path: $programFilesManager"
    Write-Step "Primary manager version: $managerVersion"
    Write-Step "Primary CLI path: $programFilesCli"
    Write-Step "Primary CLI version: $cliVersion"

    if ($managerVersion -and $managerVersion -ge $latest.Version) {
        Write-Step "SUCCESS: 7-Zip Manager updated successfully to version $managerVersion."
        Complete-Script -Code 0
        return
    }

    $preferredAfter = Get-PreferredManager
    if ($preferredAfter) {
        Write-Step "Preferred detected manager after install: $($preferredAfter.Path)"
        Write-Step "Preferred detected manager version after install: $($preferredAfter.Version)"
    }

    throw "Installer completed, but C:\Program Files\7-Zip\7zFM.exe is still not updated to the expected version."
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
