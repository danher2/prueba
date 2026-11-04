# Explain.ps1
# Select a word or phrase anywhere in Windows, press your shortcut key,
# and a small pop-up window opens with Google's English explanation.

Add-Type -AssemblyName System.Windows.Forms

# --- 1. Remember the current clipboard, then clear it -----------------------
$previous = Get-Clipboard -Raw -ErrorAction SilentlyContinue
try { [System.Windows.Forms.Clipboard]::Clear() } catch {}

# --- 2. Wait for the shortcut keys to be released, then copy the selection ---
Start-Sleep -Milliseconds 400
[System.Windows.Forms.SendKeys]::SendWait('^c')
Start-Sleep -Milliseconds 300
$text = Get-Clipboard -Raw -ErrorAction SilentlyContinue

# If nothing was copied, use what was already on the clipboard (manual Ctrl+C)
if ([string]::IsNullOrWhiteSpace($text)) { $text = $previous }
if ([string]::IsNullOrWhiteSpace($text)) { exit }

# Put the original clipboard back
if (-not [string]::IsNullOrWhiteSpace($previous)) {
    Set-Clipboard -Value $previous -ErrorAction SilentlyContinue
}

# --- 3. Clean the text --------------------------------------------------------
$text = ($text -replace '\s+', ' ').Trim()
$text = $text.Trim([char[]]'.,;:!?"''()[]{}')
if ($text.Length -gt 150) { $text = $text.Substring(0, 150) }
if ($text -eq '') { exit }

# --- 4. Build the Google search (always in English) --------------------------
$wordCount = ($text -split ' ').Count
if ($wordCount -eq 1) {
    $query = "define $text"                 # single word -> dictionary box
} else {
    $query = "what does `"$text`" mean"     # phrase -> explanation of the phrase
}
$url = 'https://www.google.com/search?hl=en&q=' + [uri]::EscapeDataString($query)

# --- 5. Open a small pop-up window near the mouse ----------------------------
$width  = 560
$height = 700
$mouse  = [System.Windows.Forms.Cursor]::Position
$area   = [System.Windows.Forms.Screen]::FromPoint($mouse).WorkingArea
$x = [Math]::Min($mouse.X + 20, $area.Right  - $width)
$y = [Math]::Min($mouse.Y + 20, $area.Bottom - $height)
$x = [Math]::Max($x, $area.Left)
$y = [Math]::Max($y, $area.Top)

$browsers = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
)
$browser = $browsers | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if ($browser) {
    # --app opens a clean window with no tabs or address bar (looks like a pop-up)
    Start-Process -FilePath $browser -ArgumentList @(
        "--app=`"$url`"",
        "--window-size=$width,$height",
        "--window-position=$x,$y"
    )
} else {
    Start-Process $url   # fallback: normal default browser
}
