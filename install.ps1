# Starts xg-autosave.ps1 now and at every Windows sign-in (via a Startup folder shortcut).
# Run again with -Uninstall to stop it and remove the shortcut.
param([switch]$Uninstall)

$script = Join-Path $PSScriptRoot 'xg-autosave.ps1'
$link = Join-Path ([Environment]::GetFolderPath('Startup')) 'XG AutoSave.lnk'
$arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""

# Stop any copy already running, so reinstalling never leaves two watchers.
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like '*xg-autosave.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

if ($Uninstall) {
    Remove-Item $link -ErrorAction SilentlyContinue
    Write-Host 'XG AutoSave stopped and removed from startup.'
    return
}

$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($link)
$shortcut.TargetPath = 'powershell.exe'
$shortcut.Arguments = $arguments
$shortcut.WindowStyle = 7
$shortcut.Save()
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList $arguments
Write-Host "XG AutoSave installed and running. Matches are saved to Documents\eXtremeGammon\Archive."
