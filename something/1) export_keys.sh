1) export_keys.sh
#!/usr/bin/env bash
set -euo pipefail

TABLE="test"
BATCH_ID="yourBatchIdValue"
PCLM_TYPE="yourPclmTypeValue"

# Remove any old output
> keys_to_update.txt

NEXT_TOKEN=""
while :; do
  if [[ -n "$NEXT_TOKEN" ]]; then
    aws dynamodb scan \
      --table-name "$TABLE" \
      --filter-expression "attribute_not_exists(expiration) AND batchID = :batchID AND PCLMType = :pclmType" \
      --expression-attribute-values '{":batchID":{"S":"'"$BATCH_ID"'"},":pclmType":{"S":"'"$PCLM_TYPE"'"}}' \
      --projection-expression "ID,ACCOUNTNUMBER" \
      --query "Items[*].[ID.S,ACCOUNTNUMBER.S]" \
      --output text \
      --starting-token "$NEXT_TOKEN" \
      >> keys_to_update.txt
  else
    aws dynamodb scan \
      --table-name "$TABLE" \
      --filter-expression "attribute_not_exists(expiration) AND batchID = :batchID AND PCLMType = :pclmType" \
      --expression-attribute-values '{":batchID":{"S":"'"$BATCH_ID"'"},":pclmType":{"S":"'"$PCLM_TYPE"'"}}' \
      --projection-expression "ID,ACCOUNTNUMBER" \
      --query "Items[*].[ID.S,ACCOUNTNUMBER.S]" \
      --output text \
      >> keys_to_update.txt
  fi

  NEXT_TOKEN=$(aws dynamodb scan \
    --table-name "$TABLE" \
    --filter-expression "attribute_not_exists(expiration) AND batchID = :batchID AND PCLMType = :pclmType" \
    --expression-attribute-values '{":batchID":{"S":"'"$BATCH_ID"'"},":pclmType":{"S":"'"$PCLM_TYPE"'"}}' \
    --projection-expression "ID" \
    --query "NextToken" \
    --output text)

  [[ -z "$NEXT_TOKEN" || "$NEXT_TOKEN" == "None" ]] && break
done

echo "Export complete: $(wc -l < keys_to_update.txt) keys written."


2) prepare_batches.sh

#!/usr/bin/env bash
set -euo pipefail

EXPIRATION=$(date -u -d "+60 days" +%s)

# Split into 25-line chunks
split -l 25 keys_to_update.txt batch_

# Build one JSON file per chunk
for chunk in batch_*; do
  jsonfile="${chunk}.json"
  {
    echo '{'
    echo '  "test": ['
    while read -r ID ACC; do
      ID=${ID//$'\r'/}
      ACC=${ACC//$'\r'/}
      cat <<EOF
    {
      "PutRequest": {
        "Item": {
          "ID": {"S": "$ID"},
          "ACCOUNTNUMBER": {"S": "$ACC"},
          "expiration": {"N": "$EXPIRATION"}
        }
      }
    },
EOF
    done < "$chunk"
    echo '  ]'
    echo '}'
  } | sed '$s/},/}/' > "$jsonfile"
  echo "Prepared $jsonfile"
done



3) run_batches.sh

#!/usr/bin/env bash
set -euo pipefail

PARALLEL=5

# Folder to hold completed batches
mkdir -p done

echo "Running batch updates with $PARALLEL parallel workers..."
# For each batch_*.json, run the write then move the file to done/
ls batch_*.json \
  | xargs -P "$PARALLEL" -n1 -I {} sh -c '
    aws dynamodb batch-write-item --request-items file://"$1" && mv "$1" done/
  ' _ {}

echo "All batches submitted."


=====================================================================
#!/usr/bin/env bash
set -euo pipefail

TABLE="test"
BATCH_ID="yourBatchIdValue"
PCLM_TYPE="yourPclmTypeValue"

# Remove any old output
> keys_to_update.txt

NEXT_TOKEN=""
while :; do
  if [[ -n "$NEXT_TOKEN" ]]; then
    aws dynamodb scan \
      --table-name "$TABLE" \
      --filter-expression "attribute_not_exists(expiration) AND batchID = :batchID AND PCLMType = :pclmType" \
      --expression-attribute-values '{":batchID":{"S":"'"$BATCH_ID"'"},":pclmType":{"S":"'"$PCLM_TYPE"'"}}' \
      --projection-expression "ID,ACCOUNTNUMBER" \
      --query "Items[*].[ID.S,ACCOUNTNUMBER.S]" \
      --output text \
      --starting-token "$NEXT_TOKEN" \
      >> keys_to_update.txt
  else
    aws dynamodb scan \
      --table-name "$TABLE" \
      --filter-expression "attribute_not_exists(expiration) AND batchID = :batchID AND PCLMType = :pclmType" \
      --expression-attribute-values '{":batchID":{"S":"'"$BATCH_ID"'"},":pclmType":{"S":"'"$PCLM_TYPE"'"}}' \
      --projection-expression "ID,ACCOUNTNUMBER" \
      --query "Items[*].[ID.S,ACCOUNTNUMBER.S]" \
      --output text \
      >> keys_to_update.txt
  fi

  # ---- begin NextToken fetch with error-catch and debug ----
  set +e
  RAW_NEXT=$(aws dynamodb scan \
    --table-name "$TABLE" \
    --filter-expression "attribute_not_exists(expiration) AND batchID = :batchID AND PCLMType = :pclmType" \
    --expression-attribute-values '{":batchID":{"S":"'"$BATCH_ID"'"},":pclmType":{"S":"'"$PCLM_TYPE"'"}}' \
    --projection-expression "ID" \
    --query "NextToken" \
    --output text 2>&1)
  RC=$?
  set -e

  echo "DEBUG: NextToken raw result=[$RAW_NEXT], rc=$RC"

  # If the call failed (e.g. because it tried to use "None" as an ExclusiveStartKey),
  # or if it returned the literal string "None", treat that as end-of-table:
  if (( RC != 0 )) || [[ "$RAW_NEXT" == "None" ]] || [[ -z "$RAW_NEXT" ]]; then
    echo "✅ Reached end of table—exported $(wc -l < keys_to_update.txt) keys."
    break
  fi

  NEXT_TOKEN=$RAW_NEXT
  # ---- end NextToken fetch ----
done

echo "Export complete: $(wc -l < keys_to_update.txt) keys written."


============================================================

#!/usr/bin/env bash
set -euo pipefail

TABLE="test"
BATCH_ID="yourBatchIdValue"
PCLM_TYPE="yourPclmTypeValue"

> keys_to_update.txt
NEXT_TOKEN=""

while :; do
  # ── 1) Fetch the actual items for this page ─────────────
  # Only include --starting-token if NEXT_TOKEN is non-empty
  if [[ -n "$NEXT_TOKEN" ]]; then
    aws dynamodb scan \
      --table-name "$TABLE" \
      --filter-expression "attribute_not_exists(expiration) AND BatchId = :batchID AND PclmType = :pclmType" \
      --expression-attribute-values '{":batchID":{"S":"'"$BATCH_ID"'"},":pclmType":{"S":"'"$PCLM_TYPE"'"}}' \
      --projection-expression "ID,ACCOUNTNUMBER" \
      --query "Items[*].[ID.S,ACCOUNTNUMBER.S]" \
      --output text \
      --starting-token "$NEXT_TOKEN" \
      >> keys_to_update.txt
  else
    aws dynamodb scan \
      --table-name "$TABLE" \
      --filter-expression "attribute_not_exists(expiration) AND BatchId = :batchID AND PclmType = :pclmType" \
      --expression-attribute-values '{":batchID":{"S":"'"$BATCH_ID"'"},":pclmType":{"S":"'"$PCLM_TYPE"'"}}' \
      --projection-expression "ID,ACCOUNTNUMBER" \
      --query "Items[*].[ID.S,ACCOUNTNUMBER.S]" \
      --output text \
      >> keys_to_update.txt
  fi

  # ── 2) Fetch the NextToken (no --starting-token here!) ─────────────
  RAW_NEXT=$(aws dynamodb scan \
    --table-name "$TABLE" \
    --filter-expression "attribute_not_exists(expiration) AND BatchId = :batchID AND PclmType = :pclmType" \
    --expression-attribute-values '{":batchID":{"S":"'"$BATCH_ID"'"},":pclmType":{"S":"'"$PCLM_TYPE"'"}}' \
    --projection-expression "ID" \
    --query "NextToken" \
    --output text)

  # ── 3) Normalize away the literal "None" or empty ─────────────
  if [[ "$RAW_NEXT" == "None" ]]; then
    RAW_NEXT=""
  fi

  # ── 4) If there is no real token, we’re done ─────────────
  if [[ -z "$RAW_NEXT" ]]; then
    echo "✅ Reached end of table—exported $(wc -l < keys_to_update.txt) keys."
    break
  fi

  # ── 5) Otherwise pass the token into the next iteration ─────────────
  NEXT_TOKEN=$RAW_NEXT
done

echo "Export complete: $(wc -l < keys_to_update.txt) keys written."

=========================================================================

=====================POWERSHELL VERSION =================================
#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Configuration
$Table    = 'test'
$BatchId  = '01'
$PclmType = 'PCLD'

# --- Prepare a valid JSON file for AWS (no BOM)
$exprFile = Join-Path $PSScriptRoot 'expr.json'
$jsonText = @"
{
  ":batchID": { "S": "$BatchId" },
  ":pclmType": { "S": "$PclmType" }
}
"@
# Write it without a BOM
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($exprFile, $jsonText, $utf8NoBom)

# --- Paging loop, writing to items_to_update.txt
$NextToken      = ''
$firstIteration = $true

while ($true) {
    # Build the scan arguments
    $scanArgs = @(
        'dynamodb','scan',
        '--table-name',        $Table,
        '--filter-expression', 'attribute_not_exists(expiration) AND BatchId = :batchID AND PclmType = :pclmType',
        '--expression-attribute-values', "file://$exprFile",
        '--projection-expression',       'ID,ACCOUNTNUMBER',
        '--query',                       'Items[*].[ID.S,ACCOUNTNUMBER.S]',
        '--output',                      'text'
    )
    if (-not [string]::IsNullOrEmpty($NextToken)) {
        $scanArgs += '--starting-token'
        $scanArgs += $NextToken
    }

    # On first iteration use > (to start on line 1), afterwards use >>
    if ($firstIteration) {
        aws @scanArgs > items_to_update.txt
        $firstIteration = $false
    }
    else {
        aws @scanArgs >> items_to_update.txt
    }

    # Fetch NextToken for pagination
    $tokenArgs = @(
        'dynamodb','scan',
        '--table-name',        $Table,
        '--filter-expression', 'attribute_not_exists(expiration) AND BatchId = :batchID AND PclmType = :pclmType',
        '--expression-attribute-values', "file://$exprFile",
        '--projection-expression',       'ID',
        '--query',                       'NextToken',
        '--output',                      'text'
    )
    $rawNext = aws @tokenArgs 2>&1

    # Trim after first newline and strip CRs
    $rawNext = ($rawNext -split "`n")[0]
    $rawNext = $rawNext -replace "`r", ''

    # Normalize literal "None"
    if ($rawNext -eq 'None') {
        $rawNext = ''
    }

    # End of table?
    if ([string]::IsNullOrEmpty($rawNext)) {
        $count = (Get-Content items_to_update.txt | Measure-Object -Line).Lines
        Write-Host "Export complete: $count items written."
        break
    }

    # Prepare for next page
    $NextToken = $rawNext
}

# --- Cleanup
Remove-Item $exprFile


===================================== CMD VERSION ====================================================

@echo off
rem -------------------------------
rem export-items.bat
rem Replicates your Bash pagination + export logic in plain CMD
rem -------------------------------
setlocal enableextensions enabledelayedexpansion

rem --- 0) Configuration
set "TABLE=test"
set "BATCH_ID=01"
set "PCLM_TYPE=PCLD"

rem --- 1) Write a clean JSON file (no BOM) for --expression-attribute-values
(
  echo {
  echo  ":batchID": { "S": "%BATCH_ID%" },
  echo  ":pclmType": { "S": "%PCLM_TYPE%" }
  echo }
) > expr.json

rem --- 2) Prepare empty output file
type nul > items_to_update.txt
set "NEXT_TOKEN="

:LOOP
  rem --- 3) Fetch one page of items
  if defined NEXT_TOKEN (
    aws dynamodb scan ^
      --table-name %TABLE% ^
      --filter-expression "attribute_not_exists(expiration) AND BatchId = :batchID AND PclmType = :pclmType" ^
      --expression-attribute-values file://expr.json ^
      --projection-expression "ID,ACCOUNTNUMBER" ^
      --query "Items[*].[ID.S,ACCOUNTNUMBER.S]" ^
      --output text ^
      --starting-token "!NEXT_TOKEN!" >> items_to_update.txt
  ) else (
    aws dynamodb scan ^
      --table-name %TABLE% ^
      --filter-expression "attribute_not_exists(expiration) AND BatchId = :batchID AND PclmType = :pclmType" ^
      --expression-attribute-values file://expr.json ^
      --projection-expression "ID,ACCOUNTNUMBER" ^
      --query "Items[*].[ID.S,ACCOUNTNUMBER.S]" ^
      --output text >> items_to_update.txt
  )

  rem --- 4) Pull out the NextToken (first line only)
  for /f "delims=" %%A in ('^
    aws dynamodb scan ^
      --table-name %TABLE% ^
      --filter-expression "attribute_not_exists(expiration) AND BatchId = :batchID AND PclmType = :pclmType" ^
      --expression-attribute-values file://expr.json ^
      --projection-expression "ID" ^
      --query "NextToken" ^
      --output text
  ^') do set "RAW_NEXT=%%A"

  rem --- 5) Normalize literal "None"
  if "!RAW_NEXT!"=="None" set "RAW_NEXT="

  rem --- 6) If no token, we’re done
  if not defined RAW_NEXT (
    for /f %%C in ('type items_to_update.txt ^| find /v /c ""') do set "COUNT=%%C"
    echo Reached end of table exported !COUNT! items.
    goto END
  )

  rem --- 7) Otherwise, loop again
  set "NEXT_TOKEN=!RAW_NEXT!"
  goto LOOP

:END
rem --- 8) Cleanup
del expr.json
endlocal
