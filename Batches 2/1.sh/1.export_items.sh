#!/usr/bin/env bash
set -euo pipefail

TABLE="test"
BATCH_ID="01"
PCLM_TYPE="PCLD"

> items_to_update.txt
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
      >> items_to_update.txt
  else
    aws dynamodb scan \
      --table-name "$TABLE" \
      --filter-expression "attribute_not_exists(expiration) AND BatchId = :batchID AND PclmType = :pclmType" \
      --expression-attribute-values '{":batchID":{"S":"'"$BATCH_ID"'"},":pclmType":{"S":"'"$PCLM_TYPE"'"}}' \
      --projection-expression "ID,ACCOUNTNUMBER" \
      --query "Items[*].[ID.S,ACCOUNTNUMBER.S]" \
      --output text \
      >> items_to_update.txt
  fi

  # ── 2) Fetch the NextToken (no --starting-token here!) ─────────────
  RAW_NEXT=$(aws dynamodb scan \
    --table-name "$TABLE" \
    --filter-expression "attribute_not_exists(expiration) AND BatchId = :batchID AND PclmType = :pclmType" \
    --expression-attribute-values '{":batchID":{"S":"'"$BATCH_ID"'"},":pclmType":{"S":"'"$PCLM_TYPE"'"}}' \
    --projection-expression "ID" \
    --query "NextToken" \
    --output text 2>&1)

  # Remove everything after the first newline  character
  RAW_NEXT=${RAW_NEXT%%$'\n'*}
  # Remove all carriage return characters
  RAW_NEXT=${RAW_NEXT//$'\r'/}

  # ── 3) Normalize away the literal "None" or empty ─────────────
  if [[ "$RAW_NEXT" == "None" ]]; then
    RAW_NEXT=""
  fi

  # ── 4) If there is no real token, we’re done ─────────────
  if [[ -z "$RAW_NEXT" ]]; then
    echo "✅ Reached end of table—exported $(wc -l < items_to_update.txt) keys."
    break
  fi

  # ── 5) Otherwise pass the token into the next iteration ─────────────
  NEXT_TOKEN=$RAW_NEXT
done

echo "Export complete: $(wc -l < items_to_update.txt) keys written."