# Setup-Explain.ps1
# Run this ONCE. It creates a Desktop shortcut that runs Explain.ps1
# when you press Ctrl+Alt+E. Keep Explain.ps1 in the same folder as this file.

$script = Join-Path $PSScriptRoot 'Explain.ps1'
if (-not (Test-Path $script)) {
    Write-Host "Explain.ps1 was not found in $PSScriptRoot" -ForegroundColor Red
    Write-Host "Put Explain.ps1 in the same folder as this setup file and run it again."
    Read-Host "Press Enter to close"
    exit
}

# Remove the 'downloaded from internet' block, if any
Unblock-File -Path $script -ErrorAction SilentlyContinue

$desktop  = [Environment]::GetFolderPath('Desktop')
$lnkPath  = Join-Path $desktop 'Explain.lnk'

$shell    = New-Object -ComObject WScript.Shell
$lnk      = $shell.CreateShortcut($lnkPath)
$lnk.TargetPath       = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$lnk.Arguments        = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
$lnk.Hotkey           = 'CTRL+ALT+E'
$lnk.WindowStyle      = 7   # start minimized
$lnk.WorkingDirectory = $PSScriptRoot
$lnk.Save()

Write-Host ""
Write-Host "Done! Shortcut created on your Desktop: $lnkPath" -ForegroundColor Green
Write-Host "Now select any word or phrase and press Ctrl+Alt+E."
Write-Host "(Do not delete or move Explain.ps1 or the Desktop shortcut.)"
Write-Host ""
Read-Host "Press Enter to close"
