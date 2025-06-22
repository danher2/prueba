# Configuration
$PARALLEL = 5
$IN_DIR = "put_batches"           # Matches the OUT_DIR from the previous script
$DONE_DIR = Join-Path $IN_DIR "done"

# Ensure the "done" directory exists
if (-not (Test-Path $DONE_DIR)) {
    New-Item -ItemType Directory -Path $DONE_DIR -Force | Out-Null
}

Write-Host "Running batch updates with $PARALLEL parallel workers..."

# Get list of put_batch_*.json files
$batchFiles = Get-ChildItem -Path "$IN_DIR/put_batch_*.json" -ErrorAction SilentlyContinue

if ($batchFiles.Count -eq 0) {
    Write-Host "No put_batch_*.json files found in $IN_DIR"
    exit 0
}

# Process files in parallel using PowerShell jobs
$jobs = @()
foreach ($file in $batchFiles) {
    # Limit the number of concurrent jobs
    while ((Get-Job -State Running).Count -ge $PARALLEL) {
        Start-Sleep -Milliseconds 100
    }

    Write-Host "Processing $($file.Name)…"
    $job = Start-Job -ScriptBlock {
        param ($filePath, $doneDir)
        try {
            # Run AWS CLI command
            $result = aws dynamodb batch-write-item --request-items file://"$filePath" 2>&1
            if ($LASTEXITCODE -eq 0) {
                # Move file to done directory on success
                Move-Item -Path $filePath -Destination $doneDir -Force
            } else {
                Write-Error "Failed to process $filePath : $result"
            }
        } catch {
            Write-Error "Failed to process $filePath : $_"
        }
    } -ArgumentList $file.FullName, $DONE_DIR

    $jobs += $job
}

# Wait for all jobs to complete
$jobs | Wait-Job | Out-Null

# Collect and display any errors
$errors = $jobs | Receive-Job | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }
if ($errors) {
    Write-Host "Some batches failed to process. Check errors above."
}

# Clean up jobs
$jobs | Remove-Job

Write-Host "All batches submitted."