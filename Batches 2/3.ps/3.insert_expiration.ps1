# Configuration
$TABLE_NAME = "test"                        # DynamoDB table name
$OUT_DIR = "put_batches"                    # Directory for output batch files
$CHUNK_SIZE = 25                            # Max items per batch
$INPUT_DIR = "batch_items"                  # Directory containing resp_*.json files

# Calculate expiration timestamp (e.g., now + 60 days)
$epoch = [datetime]::UnixEpoch  # Define Unix epoch (1970-01-01)
if (-not $epoch) {
    $epoch = [datetime]::new(1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
}
$EXPIRATION = [int64]((Get-Date).AddDays(60).ToUniversalTime().Subtract($epoch).TotalSeconds)

# Ensure output directory exists
if (-not (Test-Path $OUT_DIR)) {
    New-Item -ItemType Directory -Path $OUT_DIR -Force | Out-Null
}

# Check if input directory exists and contains resp_*.json files
$jsonFiles = Get-ChildItem -Path "$INPUT_DIR/resp_*.json" -ErrorAction SilentlyContinue
if (-not (Test-Path $INPUT_DIR) -or $jsonFiles.Count -eq 0) {
    Write-Host "❌ Error: No resp_*.json files found in $INPUT_DIR"
    exit 1
}

# Process each resp_*.json file
foreach ($RESP_FILE in $jsonFiles) {
    # Extract file number (e.g., "1" from "resp_1.json")
    $FILE_BASE = $RESP_FILE.BaseName -replace '^resp_', ''
    Write-Host "Processing $($RESP_FILE.Name) (File $FILE_BASE)"

    try {
        # Read JSON file
        $jsonContent = Get-Content $RESP_FILE.FullName -Raw | ConvertFrom-Json -ErrorAction Stop

        # Check if Responses and table exist
        if (-not $jsonContent.PSObject.Properties.Name.Contains("Responses") -or 
            -not $jsonContent.Responses.PSObject.Properties.Name.Contains($TABLE_NAME)) {
            Write-Warning "No valid Responses.$TABLE_NAME found in $($RESP_FILE.Name)"
            continue
        }

        # Process items:
        # 1) Select the items array under .Responses[$TABLE_NAME]
        # 2) Inject an "expiration" field into each non-null item
        # 3) Wrap each item in a PutRequest structure
        # 4) Split into batches of $CHUNK_SIZE
        $items = $jsonContent.Responses.$TABLE_NAME
        if ($null -eq $items -or $items.Count -eq 0) {
            Write-Warning "Empty or null items in Responses.$TABLE_NAME for $($RESP_FILE.Name)"
            continue
        }

        $itemsWithExpiration = $items | Where-Object { $_ -ne $null } | ForEach-Object {
            try {
                $item = $_
                if ($item -is [PSCustomObject]) {
                    $item | Add-Member -MemberType NoteProperty -Name expiration -Value @{ N = $EXPIRATION.ToString() } -PassThru
                } else {
                    Write-Warning "Skipping invalid item in $($RESP_FILE.Name): not a valid object"
                    $null
                }
            } catch {
                Write-Warning "Error processing item in $($RESP_FILE.Name): $_"
                $null
            }
        } | Where-Object { $_ -ne $null }

        if ($itemsWithExpiration.Count -eq 0) {
            Write-Warning "No valid items to process in $($RESP_FILE.Name)"
            continue
        }

        $putRequests = $itemsWithExpiration | ForEach-Object {
            @{ PutRequest = @{ Item = $_ } }
        }

        # Split into chunks
        $batches = for ($i = 0; $i -lt $putRequests.Count; $i += $CHUNK_SIZE) {
            @{ $TABLE_NAME = $putRequests[$i..($i + $CHUNK_SIZE - 1)] }
        }

        # Write each batch to its own file
        $batch_index = 1
        foreach ($batch in $batches) {
            $batch | ConvertTo-Json -Compress -Depth 10 | Out-File "$OUT_DIR/put_batch_resp${FILE_BASE}_${batch_index}.json" -Encoding utf8
            $batch_index++
        }
    }
    catch {
        Write-Error "Failed to process $($RESP_FILE.Name): $_"
        continue
    }
}

# Summary: count files in OUT_DIR
$batchCount = (Get-ChildItem $OUT_DIR -ErrorAction SilentlyContinue | Measure-Object).Count
Write-Host "✅ Generated $batchCount batch files in $OUT_DIR"




==================================================

# Configuration
$TABLE_NAME = "test"                        # DynamoDB table name
$OUT_DIR = "put_batches"                    # Directory for output batch files
$CHUNK_SIZE = 25                            # Max items per batch
$INPUT_DIR = "batch_items"                  # Directory containing resp_*.json files

# Calculate expiration timestamp (e.g., now + 60 days)
$epoch = [datetime]::UnixEpoch  # Define Unix epoch (1970-01-01)
if (-not $epoch) {
    $epoch = [datetime]::new(1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
}
$EXPIRATION = [int64]((Get-Date).AddDays(60).ToUniversalTime().Subtract($epoch).TotalSeconds)

# Ensure output directory exists
if (-not (Test-Path $OUT_DIR)) {
    New-Item -ItemType Directory -Path $OUT_DIR -Force | Out-Null
}

# Check if input directory exists and contains resp_*.json files
$jsonFiles = Get-ChildItem -Path "$INPUT_DIR/resp_*.json" -ErrorAction SilentlyContinue
if (-not (Test-Path $INPUT_DIR) -or $jsonFiles.Count -eq 0) {
    Write-Host "❌ Error: No resp_*.json files found in $INPUT_DIR"
    exit 1
}

# Process each resp_*.json file
foreach ($RESP_FILE in $jsonFiles) {
    # Extract file number (e.g., "1" from "resp_1.json")
    $FILE_BASE = $RESP_FILE.BaseName -replace '^resp_', ''
    Write-Host "Processing $($RESP_FILE.Name) (File $FILE_BASE)"

    try {
        # Read JSON file
        $jsonContent = Get-Content $RESP_FILE.FullName -Raw | ConvertFrom-Json -ErrorAction Stop

        # Check if Responses and table exist
        if (-not $jsonContent.PSObject.Properties.Name.Contains("Responses") -or 
            -not $jsonContent.Responses.PSObject.Properties.Name.Contains($TABLE_NAME)) {
            Write-Warning "No valid Responses.$TABLE_NAME found in $($RESP_FILE.Name)"
            continue
        }

        # Process items:
        $items = $jsonContent.Responses.$TABLE_NAME
        if ($null -eq $items -or $items.Count -eq 0) {
            Write-Warning "Empty or null items in Responses.$TABLE_NAME for $($RESP_FILE.Name)"
            continue
        }

        $itemsWithExpiration = $items | Where-Object { $_ -ne $null } | ForEach-Object {
            try {
                $item = $_
                if ($item -is [PSCustomObject]) {
                    $item | Add-Member -MemberType NoteProperty -Name expiration -Value @{ N = $EXPIRATION.ToString() } -PassThru
                } else {
                    Write-Warning "Skipping invalid item in $($RESP_FILE.Name): not a valid object"
                    $null
                }
            } catch {
                Write-Warning "Error processing item in $($RESP_FILE.Name): $_"
                $null
            }
        } | Where-Object { $_ -ne $null }

        if ($itemsWithExpiration.Count -eq 0) {
            Write-Warning "No valid items to process in $($RESP_FILE.Name)"
            continue
        }

        # The important fix is right here:
        $putRequests = @($itemsWithExpiration | ForEach-Object {
            @{ PutRequest = @{ Item = $_ } }
        })

        # Split into chunks
        $batches = for ($i = 0; $i -lt $putRequests.Count; $i += $CHUNK_SIZE) {
            @{ $TABLE_NAME = $putRequests[$i..([Math]::Min($i + $CHUNK_SIZE - 1, $putRequests.Count - 1))] }
        }

        # Write each batch to its own file
        $batch_index = 1
        foreach ($batch in $batches) {
            $batch | ConvertTo-Json -Compress -Depth 10 | Out-File "$OUT_DIR/put_batch_resp${FILE_BASE}_${batch_index}.json" -Encoding utf8
            $batch_index++
        }
    }
    catch {
        Write-Error "Failed to process $($RESP_FILE.Name): $_"
        continue
    }
}

# Summary: count files in OUT_DIR
$batchCount = (Get-ChildItem $OUT_DIR -ErrorAction SilentlyContinue | Measure-Object).Count
Write-Host "✅ Generated $batchCount batch files in $OUT_DIR"
