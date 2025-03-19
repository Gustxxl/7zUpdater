### To use the script, enter this command in powershell an administrator
```powershell
irm "https://raw.githubusercontent.com/Gustxxl/7zUpdater/refs/heads/main/7zUpdater.ps1" | iex
```

# PowerShell Script: Auto-Update 7-Zip to the Latest Version

### Overview:

This PowerShell script automatically downloads and installs the latest version of 7-Zip without requiring manual updates to the download link. It fetches the latest available version from the official 7-Zip download page, installs it in silent mode, and verifies the installation.

⸻

How the Script Works:

	1.	Fetch the latest version URL
	•	The script accesses the official 7-Zip download page and extracts the latest .exe installer link.
	•	It eliminates the need for manual URL updates when a new version is released.
	2.	Check the currently installed version
	•	If 7-Zip is installed, the script retrieves its version by running 7z.exe and extracting the version number.
	3.	Download the latest installer
	•	Using Invoke-WebRequest, the script downloads the latest available 7-Zip installer to the system’s temporary folder.
	4.	Install 7-Zip silently
	•	The installer runs with the /S (silent) argument, meaning no user interaction is required.
	5.	Verify the installation
	•	After installation, the script retrieves the installed 7-Zip version again to confirm that the update was successful.
	6.	Cleanup
	•	The installer file is deleted to free up space.
	7.	Final confirmation
	•	If the version has changed, it confirms the update. Otherwise, it notifies that the version remains the same.

⸻

### Use Case Scenarios:

✅ Automated software updates – Keeps 7-Zip up to date without manual intervention.
✅ System administrators – Useful for deploying updates on multiple machines.
✅ Scripting enthusiasts – Demonstrates web scraping, file management, and process execution in PowerShell.

⸻

### Key Features & Benefits:

✔ Automatic version detection – Always fetches the latest version from the official website.
✔ Silent installation – Installs without user input.
✔ Version validation – Ensures the update was applied successfully.
✔ No manual URL updates required – Saves time by dynamically retrieving the latest version.

#### This script is a fully automated solution for keeping 7-Zip updated on Windows! 🚀
