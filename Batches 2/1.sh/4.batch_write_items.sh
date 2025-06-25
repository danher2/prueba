#!/usr/bin/env bash
set -euo pipefail

PARALLEL=5
IN_DIR="put_batches"           # ← now matches your jq script’s OUT_DIR
DONE_DIR="$IN_DIR/done"

# Ensure the “done” directory exists
mkdir -p "$DONE_DIR"

echo "Running batch updates with $PARALLEL parallel workers..."

# Process each put_batch_*.json under put_batches/, then move it to done/ on success
ls "$IN_DIR"/put_batch_*.json \
  | xargs -P "$PARALLEL" -n1 -I {} bash -c '
      echo "Processing $1…"
      if aws dynamodb batch-write-item --request-items file://"$1"; then
        mv "$1" "'"$DONE_DIR"'"
      else
        echo "Failed to process $1" >&2
      fi
    ' _ {}

echo "All batches submitted."