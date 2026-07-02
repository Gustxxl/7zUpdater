# Define 7-Zip official download page URL
$downloadPageUrl = "https://www.7-zip.org/download.html"
$installerPath = "$env:TEMP\7zip-installer.exe"
$7zipExe = "C:\Program Files\7-Zip\7z.exe"

# Function to get the installed version of 7-Zip
function Get-7ZipVersion {
    if (Test-Path $7zipExe) {
        $versionOutput = (& $7zipExe) -join "`n"
        # Match e.g. "7-Zip 24.09 (x64)" -> 24.09
        $match = [regex]::Match($versionOutput, "7-Zip\s+(\d+\.\d+)")
        if ($match.Success) {
            return $match.Groups[1].Value
        }
    }
    return $null
}

# Fetch the latest version download link
Write-Host "Fetching the latest 7-Zip download URL..."
$downloadPageContent = Invoke-WebRequest -Uri $downloadPageUrl -UseBasicParsing

# Find all x64 .exe installer links, pick the highest version number
$candidates = $downloadPageContent.Links |
    Where-Object { $_.href -match "a/7z(\d+)-x64\.exe$" } |
    ForEach-Object {
        [void]($_.href -match "a/7z(\d+)-x64\.exe$")
        [PSCustomObject]@{
            Href       = $_.href
            VersionNum = [int]$matches[1]
        }
    } |
    Sort-Object VersionNum -Descending

if (-not $candidates) {
    Write-Host "Could not find a download link on the page. Aborting."
    exit 1
}

$relativeUrl = $candidates[0].Href
$downloadUrl = "https://www.7-zip.org/$relativeUrl"

# Get the currently installed version
$currentVersion = Get-7ZipVersion
Write-Host "Current 7-Zip version: $currentVersion (x64)"

# Download the latest installer
Write-Host "Downloading 7-Zip from $downloadUrl..."
Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath

# Install 7-Zip silently
Write-Host "Installing 7-Zip..."
Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait

# Get the new installed version
$newVersion = Get-7ZipVersion
Write-Host "New 7-Zip version: $newVersion (x64)"

# Remove the installer file
Write-Host "Cleaning up installer file..."
Remove-Item -Path $installerPath -Force

# Final confirmation message
if ($newVersion -ne $currentVersion) {
    Write-Host "7-Zip successfully updated to version $newVersion"
} else {
    Write-Host "7-Zip version remains the same. No update needed."
}
