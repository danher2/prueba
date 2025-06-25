#!/usr/bin/env bash

# ── Configuration ───────────────────────────────────────────
TABLE="test"
IN_FILE="items_to_update.txt"
WORKDIR="batch_items"
BATCH_SIZE_GET=100
mkdir -p "$WORKDIR"

# ── Normalize line endings ─────────────────────────────────
dos2unix "$IN_FILE" 2>/dev/null || sed -i 's/\r$//' "$IN_FILE"

# ── Read input into array ──────────────────────────────────
mapfile -t LINES < "$IN_FILE"
TOTAL=${#LINES[@]}
echo "Total items to process: $TOTAL"

# ── Process in batches of 100 ──────────────────────────────
get_batch_num=0

for ((i=0; i<TOTAL; i+=BATCH_SIZE_GET)); do
  ((get_batch_num++))
  echo "Processing batch-get #$get_batch_num"
  KEYS=()

  # Build keys for batch-get
  for ((j=0; j<BATCH_SIZE_GET && i+j<TOTAL; j++)); do
    line="${LINES[i+j]}"
    IFS=$'\t' read -r ID ACC <<< "$line"

    if [[ -z "$ID" || -z "$ACC" ]]; then
      echo "❌ Malformed line: '$line'"
      continue
    fi

    KEYS+=("{\"ID\":{\"S\":\"$ID\"},\"ACCOUNTNUMBER\":{\"S\":\"$ACC\"}}")
  done

  # Skip if no valid keys
  if [ ${#KEYS[@]} -eq 0 ]; then
    echo "No valid keys in batch #$get_batch_num, skipping"
    continue
  fi

  # Create batch-get JSON
  GET_JSON="$WORKDIR/get_batch_${get_batch_num}.json"
  {
    echo -n '{ "'$TABLE'": { "Keys": ['
    for ((k=0; k<${#KEYS[@]}; k++)); do
      echo -n "${KEYS[k]}"
      [[ $k -lt $((${#KEYS[@]} - 1)) ]] && echo -n ','
    done
    echo '] } }'
  } > "$GET_JSON"

  echo "📄 Generated JSON for batch #$get_batch_num:"
  cat "$GET_JSON"

  # Execute batch-get and save response
  RESP=$(aws dynamodb batch-get-item --request-items "file://$GET_JSON")
  echo "$RESP" > "$WORKDIR/resp_${get_batch_num}.json"
  echo "🟢 Response saved to resp_${get_batch_num}.json"

  # Remove temporary get batch file
  rm "$GET_JSON"
  echo "🗑️ Removed temporary file $GET_JSON"
done

echo "✅ All batch-get responses saved in $WORKDIR"