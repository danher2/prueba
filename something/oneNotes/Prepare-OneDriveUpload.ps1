<#
  Prepare-OneDriveUpload.ps1

  Collects only the My Notes files that are NEW or CHANGED since the last time
  you ran it, into a folder ready to upload to OneDrive:

      Desktop\MyNotes-Upload\MyNotes\   (same folder layout as your notes)

  Then upload that MyNotes folder at onedrive.com, in the same place as your
  existing MyNotes folder. OneDrive merges it in: new files are added, and for
  changed ones you choose "Replace".

  Usage:
      powershell -ExecutionPolicy Bypass -File .\Prepare-OneDriveUpload.ps1
  Options:
      -All      take every file (a full upload)
      -Redo     take again what the previous run took (if that upload failed)
      -NotesFolder "C:\path\to\MyNotes"     if your notes are somewhere else

  It only reads your notes and copies them; it never changes or deletes them.
#>
param(
    [string]$NotesFolder = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'OneDrive\MyNotes'),
    [string]$OutFolder = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'MyNotes-Upload'),
    [switch]$All,
    [switch]$Redo
)

$ErrorActionPreference = 'Stop'
$userHome = [Environment]::GetFolderPath('UserProfile')

if (-not (Test-Path -LiteralPath $NotesFolder -PathType Container)) {
    Write-Host "Notes folder not found: $NotesFolder" -ForegroundColor Red
    Write-Host 'Run it again with -NotesFolder "C:\path\to\MyNotes" (the folder shown at the bottom of My Notes).'
    exit 1
}
$NotesFolder = (Resolve-Path -LiteralPath $NotesFolder).Path.TrimEnd('\', '/')
$OutFolder = [IO.Path]::GetFullPath($OutFolder).TrimEnd('\', '/')
if ($OutFolder.StartsWith($NotesFolder, [StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "The upload folder can't be inside the notes folder." -ForegroundColor Red
    exit 1
}

# What was uploaded last time is remembered here (one line per file: path, size, time).
$stateDir = Join-Path $userHome '.mynotes'
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
$manifest = Join-Path $stateDir 'onedrive-upload-manifest.csv'
$previous = Join-Path $stateDir 'onedrive-upload-manifest.previous.csv'

function Read-Manifest([string]$path) {
    $map = @{}
    if (Test-Path -LiteralPath $path) {
        foreach ($row in (Import-Csv -LiteralPath $path)) { $map[$row.Path] = $row.Length + '|' + $row.Ticks }
    }
    return $map
}

$compareWith = if ($Redo) { $previous } else { $manifest }
$known = if ($All) { @{} } else { Read-Manifest $compareWith }
$firstRun = (-not $All) -and $known.Count -eq 0

# Every file in the notes folder, except deleted items (_Trash) and the app's temporary files.
$sep = [IO.Path]::DirectorySeparatorChar
$files = Get-ChildItem -LiteralPath $NotesFolder -Recurse -File -Force | Where-Object {
    $rel = $_.FullName.Substring($NotesFolder.Length + 1)
    -not ($rel -eq '_Trash' -or $rel.StartsWith('_Trash' + $sep)) -and $_.Name -notlike '.tmp-*' -and $_.Name -notlike '.rename-*'
}

$current = New-Object System.Collections.Generic.List[object]
$toCopy = New-Object System.Collections.Generic.List[object]
$new = 0; $changed = 0
foreach ($f in $files) {
    $rel = $f.FullName.Substring($NotesFolder.Length + 1)
    $sig = [string]$f.Length + '|' + [string]$f.LastWriteTimeUtc.Ticks
    $current.Add([pscustomobject]@{ Path = $rel; Length = $f.Length; Ticks = $f.LastWriteTimeUtc.Ticks })
    if (-not $known.ContainsKey($rel)) { $toCopy.Add($f); $new++ }
    elseif ($known[$rel] -ne $sig) { $toCopy.Add($f); $changed++ }
}

# Fresh upload folder each time
if (Test-Path -LiteralPath $OutFolder) { Remove-Item -LiteralPath $OutFolder -Recurse -Force }
$target = Join-Path $OutFolder 'MyNotes'
New-Item -ItemType Directory -Path $target -Force | Out-Null

$bytes = 0
foreach ($f in $toCopy) {
    $rel = $f.FullName.Substring($NotesFolder.Length + 1)
    $dest = Join-Path $target $rel
    New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
    Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
    $bytes += $f.Length
}

# Remember this run (keep the one before, for -Redo)
if (-not $Redo) {
    if (Test-Path -LiteralPath $manifest) { Copy-Item -LiteralPath $manifest -Destination $previous -Force }
    $current | Export-Csv -LiteralPath $manifest -NoTypeInformation -Encoding UTF8
}
$listFile = Join-Path $OutFolder 'files-in-this-upload.txt'
($toCopy | ForEach-Object { $_.FullName.Substring($NotesFolder.Length + 1) }) | Set-Content -LiteralPath $listFile -Encoding UTF8

Write-Host ''
if ($toCopy.Count -eq 0) {
    Write-Host 'Nothing new or changed since the last upload. Nothing to do.' -ForegroundColor Green
    Remove-Item -LiteralPath $OutFolder -Recurse -Force
    exit 0
}
if ($All) { Write-Host ("Full upload: {0} files ({1:N1} MB)." -f $toCopy.Count, ($bytes / 1MB)) -ForegroundColor Cyan }
elseif ($firstRun) { Write-Host ("First run, so this is everything: {0} files ({1:N1} MB)." -f $toCopy.Count, ($bytes / 1MB)) -ForegroundColor Cyan }
else { Write-Host ("{0} new and {1} changed files ({2:N1} MB) since the last upload." -f $new, $changed, ($bytes / 1MB)) -ForegroundColor Cyan }
Write-Host ''
Write-Host 'Now upload it:' -ForegroundColor Yellow
Write-Host '  1. Open onedrive.com and go to the folder that CONTAINS your MyNotes folder (for example My files).'
Write-Host "  2. Click Upload > Folder and choose:  $target"
Write-Host '  3. If OneDrive asks about files that already exist, choose Replace (tick "apply to all").'
Write-Host ''
Write-Host "The list of files in this upload is in: $listFile"
Write-Host 'If the upload fails, run this script again with -Redo to rebuild the same set.'
try { Invoke-Item -LiteralPath $OutFolder } catch { }
