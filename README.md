# 7zUpdater

A PowerShell script that installs or updates 7-Zip to the latest available x64 release on Windows.

## Run

Open PowerShell and run:

```powershell
irm "https://raw.githubusercontent.com/Gustxxl/7zUpdater/refs/heads/main/7zUpdater.ps1" | iex
```

The script will relaunch itself as Administrator automatically if needed.

## What It Does

* Detects the currently installed 7-Zip version from standard installation paths
* Retrieves the latest available release from the official `ip7z/7zip` GitHub Releases API
* Downloads the latest x64 installer dynamically without hardcoded version numbers
* Stops running 7-Zip processes before installation
* Runs the installer silently using `/S`
* Verifies that the installed version was updated successfully
* Removes the temporary installer file after completion

## How It Works

1. Checks whether the script is running with Administrator privileges
2. Looks for 7-Zip in the standard install locations:
    * `C:\Program Files\7-Zip\7zFM.exe`
    * `C:\Program Files\7-Zip\7z.exe`
    * `C:\Program Files (x86)\7-Zip\7zFM.exe`
    * `C:\Program Files (x86)\7-Zip\7z.exe`
3. Reads version information from file metadata instead of launching 7-Zip executables
4. Queries the latest release from the official GitHub API
5. Selects the latest x64 installer asset automatically
6. Stops running 7-Zip processes if needed
7. Downloads the installer to the temporary folder
8. Installs 7-Zip silently
9. Verifies the installed version
10. Deletes the temporary installer file

## Features

* No hardcoded installer version
* Silent installation
* Automatic elevation
* Safe version detection through file metadata
* No transcript or log-file creation
* Temporary installer cleanup
* Explicit verification of the installed 7-Zip Manager version

## Requirements

* Windows
* PowerShell 5.1 or later
* Internet access
* Administrator privileges

## Notes

* The script installs the latest available **x64** release of 7-Zip.
* The primary installed version is verified using:
    * `C:\Program Files\7-Zip\7zFM.exe`
* A temporary installer is created in `%TEMP%` during the update process and removed afterwards.
* If another copy of 7-Zip exists outside the standard installation path, it is not treated as the primary installed version.

## Example

```powershell
irm "https://raw.githubusercontent.com/Gustxxl/7zUpdater/refs/heads/main/7zUpdater.ps1" | iex
```
