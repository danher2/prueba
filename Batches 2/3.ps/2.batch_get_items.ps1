# Configuration
$TABLE = "test"
$IN_FILE = "items_to_update.txt"
$WORKDIR = "batch_items"
$BATCH_SIZE_GET = 100

# Ensure working directory exists
New-Item -ItemType Directory -Force -Path $WORKDIR | Out-Null

# Normalize line endings (PowerShell natively handles both CRLF and LF)
(Get-Content -Raw -Encoding UTF8 $IN_FILE) -replace "\r" | Set-Content -Encoding UTF8 $IN_FILE

# Read lines
$LINES = Get-Content -Path $IN_FILE
$TOTAL = $LINES.Count
Write-Host "Total items to process: $TOTAL"

# Process in batches
$get_batch_num = 0
for ($i = 0; $i -lt $TOTAL; $i += $BATCH_SIZE_GET) {
    $get_batch_num++
    Write-Host "Processing batch-get #$get_batch_num"
    $KEYS = @()

    for ($j = 0; $j -lt $BATCH_SIZE_GET -and ($i + $j) -lt $TOTAL; $j++) {
        $line = $LINES[$i + $j]

		# Skip blank lines immediately
		if ([string]::IsNullOrWhiteSpace($line)) {
			continue
		}

		$fields = $line -split "`t"

		if ($fields.Count -ne 2 -or [string]::IsNullOrWhiteSpace($fields[0]) -or [string]::IsNullOrWhiteSpace($fields[1])) {
			Write-Warning "❌ Malformed line: '$line'"
			continue
		}


        $ID = $fields[0].Trim()
        $ACC = $fields[1].Trim()

        $key = @{ ID = @{ S = $ID }; ACCOUNTNUMBER = @{ S = $ACC } } | ConvertTo-Json -Compress
        $KEYS += $key
    }

    if ($KEYS.Count -eq 0) {
        Write-Host "No valid keys in batch #$get_batch_num, skipping"
        continue
    }

    $keysJson = ($KEYS -join ",")
    $jsonContent = "{ `"$TABLE`": { `"Keys`": [ $keysJson ] } }"

    $GET_JSON = "$WORKDIR/get_batch_${get_batch_num}.json"
    Set-Content -Path $GET_JSON -Value $jsonContent -Encoding utf8NoBOM

    Write-Host "📄 Generated JSON for batch #${get_batch_num}:"
    Get-Content $GET_JSON | Write-Host

    $RESP = aws dynamodb batch-get-item --request-items file://$GET_JSON
    $RESP | Set-Content -Path "$WORKDIR/resp_${get_batch_num}.json" -Encoding utf8NoBOM
    Write-Host "🟢 Response saved to resp_${get_batch_num}.json"

    Remove-Item -Path $GET_JSON
    Write-Host "🗑️ Removed temporary file $GET_JSON"
}

Write-Host "✅ All batch-get responses saved in $WORKDIR"

====================================================================

# Configuration
$TABLE = "test"
$IN_FILE = "items_to_update.txt"
$WORKDIR = "batch_items"
$BATCH_SIZE_GET = 100

# Ensure working directory exists
New-Item -ItemType Directory -Force -Path $WORKDIR | Out-Null

# Normalize line endings (PowerShell natively handles both CRLF and LF)
(Get-Content -Raw -Encoding UTF8 $IN_FILE) -replace "\r" | Set-Content -Encoding UTF8 $IN_FILE

# Read lines
$LINES = Get-Content -Path $IN_FILE | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$TOTAL = $LINES.Count
Write-Host "Total items to process: $TOTAL"

# Process in batches
$get_batch_num = 0
for ($i = 0; $i -lt $TOTAL; $i += $BATCH_SIZE_GET) {
    $get_batch_num++
    Write-Host "Processing batch-get #$get_batch_num"
    $KEYS = @()

    for ($j = 0; $j -lt $BATCH_SIZE_GET -and ($i + $j) -lt $TOTAL; $j++) {
        $line = $LINES[$i + $j]

		# Skip blank lines immediately
		if ([string]::IsNullOrWhiteSpace($line)) {
			continue
		}

		$fields = $line -split "`t"

		if ($fields.Count -ne 2 -or [string]::IsNullOrWhiteSpace($fields[0]) -or [string]::IsNullOrWhiteSpace($fields[1])) {
			Write-Warning "❌ Malformed line: '$line'"
			continue
		}


        $ID = $fields[0].Trim()
        $ACC = $fields[1].Trim()

        $key = @{ ID = @{ S = $ID }; ACCOUNTNUMBER = @{ S = $ACC } } | ConvertTo-Json -Compress
        $KEYS += $key
    }

    if ($KEYS.Count -eq 0) {
        Write-Host "No valid keys in batch #$get_batch_num, skipping"
        continue
    }

    $keysJson = ($KEYS -join ",")
    $jsonContent = "{ `"$TABLE`": { `"Keys`": [ $keysJson ] } }"

    $GET_JSON = "$WORKDIR/get_batch_${get_batch_num}.json"
    Set-Content -Path $GET_JSON -Value $jsonContent -Encoding utf8NoBOM

    Write-Host "📄 Generated JSON for batch #${get_batch_num}:"
    Get-Content $GET_JSON | Write-Host

    $RESP = aws dynamodb batch-get-item --request-items file://$GET_JSON
    $RESP | Set-Content -Path "$WORKDIR/resp_${get_batch_num}.json" -Encoding utf8NoBOM
    Write-Host "🟢 Response saved to resp_${get_batch_num}.json"

    Remove-Item -Path $GET_JSON
    Write-Host "🗑️ Removed temporary file $GET_JSON"
}

Write-Host "✅ All batch-get responses saved in $WORKDIR"

