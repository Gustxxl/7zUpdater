# Define 7-Zip official download page URL
$downloadPageUrl = "https://www.7-zip.org/download.html"
$installerPath = "$env:TEMP\7zip-installer.exe"
$7zipExe = "C:\Program Files\7-Zip\7z.exe"

# Function to get the installed version of 7-Zip
function Get-7ZipVersion {
    if (Test-Path $7zipExe) {
        $versionOutput = & $7zipExe | Select-String "7-Zip"
        if ($versionOutput) {
            return ($versionOutput -split " ")[2]  # Extract version number
        }
    }
    return $null
}

# Fetch the latest version download link
Write-Host "Fetching the latest 7-Zip download URL..."
$downloadPageContent = Invoke-WebRequest -Uri $downloadPageUrl -UseBasicParsing
$downloadUrl = $downloadPageContent.Links | Where-Object { $_.href -match "a/7z\d+-x64.exe" } | Select-Object -ExpandProperty href -First 1
$downloadUrl = "https://www.7-zip.org/$downloadUrl"

# Get the currently installed version
$currentVersion = Get-7ZipVersion
Write-Host "Current 7-Zip version: $currentVersion"

# Download the latest installer
Write-Host "Downloading 7-Zip from $downloadUrl..."
Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath

# Install 7-Zip silently
Write-Host "Installing 7-Zip..."
Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait

# Get the new installed version
$newVersion = Get-7ZipVersion
Write-Host "New 7-Zip version: $newVersion"

# Remove the installer file
Write-Host "Cleaning up installer file..."
Remove-Item -Path $installerPath -Force

# Final confirmation message
if ($newVersion -ne $currentVersion) {
    Write-Host "7-Zip successfully updated to version $newVersion"
} else {
    Write-Host "7-Zip version remains the same. No update needed."
}
