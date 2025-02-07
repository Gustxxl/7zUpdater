# Определяем URL последней версии 7-Zip (замените ссылку при обновлении)
$downloadUrl = "https://www.7-zip.org/a/7z2409-x64.exe"  # Актуальную версию можно проверить на сайте 7-Zip
$installerPath = "$env:TEMP\7zip-installer.exe"
$7zipExe = "C:\Program Files\7-Zip\7z.exe"

# Функция получения установленной версии 7-Zip
function Get-7ZipVersion {
    if (Test-Path $7zipExe) {
        $versionOutput = & $7zipExe | Select-String "7-Zip"
        if ($versionOutput) {
            return ($versionOutput -split " ")[2]  # Получаем номер версии
        }
    }
    return $null
}

# Получаем текущую версию 7-Zip
$currentVersion = Get-7ZipVersion
Write-Host "Текущая версия 7-Zip: $currentVersion"

# Загружаем установочный файл
Write-Host "Скачивание 7-Zip с $downloadUrl..."
Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath

# Запускаем установку в тихом режиме
Write-Host "Установка 7-Zip..."
Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait

# Проверяем новую версию после установки
$newVersion = Get-7ZipVersion
Write-Host "Новая версия 7-Zip: $newVersion"

# Удаляем установочный файл
Write-Host "Очистка установочного файла..."
Remove-Item -Path $installerPath -Force

# Завершаем выполнение
if ($newVersion -ne $currentVersion) {
    Write-Host "7-Zip успешно обновлён до версии $newVersion"
} else {
    Write-Host "Версия 7-Zip не изменилась. Возможно, обновление не требуется."
}
