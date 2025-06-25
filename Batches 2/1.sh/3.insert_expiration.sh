#!/usr/bin/env bash

# Configuration
TABLE_NAME="test"                        # DynamoDB table name
OUT_DIR="put_batches"                    # Directory for output batch files
CHUNK_SIZE=25                            # Max items per batch
INPUT_DIR="batch_items"                  # Directory containing resp_*.json files

# Calculate expiration timestamp (e.g., now + 60 days)
EXPIRATION=$(date -d "+60 days" +%s)

# Ensure output directory exists
mkdir -p "$OUT_DIR"

# Check if input directory exists and contains resp_*.json files
if [ ! -d "$INPUT_DIR" ] || [ -z "$(ls -A "$INPUT_DIR"/resp_*.json 2>/dev/null)" ]; then
  echo "❌ Error: No resp_*.json files found in $INPUT_DIR"
  exit 1
fi

# Process each resp_*.json file
for RESP_FILE in "$INPUT_DIR"/resp_*.json; do
  # Extract file number (e.g., "1" from "resp_1.json")
  FILE_BASE=$(basename "$RESP_FILE" .json | sed 's/resp_//')
  echo "Processing $RESP_FILE (File $FILE_BASE)"

  # Use jq to:
  # 1) Select the items array under .Responses[TABLE_NAME]
  # 2) Inject an "expiration" field into each item
  # 3) Wrap each item in a PutRequest structure
  # 4) Split the list into batches of CHUNK_SIZE
  BATCHES_JSON=$(jq --arg exp "$EXPIRATION" \
                  --arg table "$TABLE_NAME" \
                  --argjson size "$CHUNK_SIZE" \
  '.Responses[$table]                            # select items array
  | map(. + { expiration: { N: $exp } })        # add expiration to each
  | map({ PutRequest: { Item: . } })            # wrap in PutRequest
  | [ range(0; length; $size) as $i              # for each batch
      | { ($table): .[$i : ($i + $size)] }       # <<–– no more “RequestItems” key
    ]' "$RESP_FILE")


  # Stream each batch as compact JSON and write to its own file
  batch_index=1
  printf '%s' "$BATCHES_JSON" | jq -c '.[]' | while read -r batch; do
    printf '%s\n' "$batch" > "$OUT_DIR/put_batch_resp${FILE_BASE}_${batch_index}.json"
    #echo "  Generated $OUT_DIR/put_batch_resp${FILE_BASE}_${batch_index}.json"
    batch_index=$((batch_index + 1))
  done
done

# Summary: count files in OUT_DIR
echo "✅ Generated $(ls "$OUT_DIR" | wc -l) batch files in $OUT_DIR"