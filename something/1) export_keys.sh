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

RAW_NEXT=${RAW_NEXT%%$'\n'*}


