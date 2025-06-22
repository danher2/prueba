#!/usr/bin/env bash
TABLE="test"

START=20
END=$((START + 200 - 1))

for i in $(seq $START $END); do
  ID="ID$i"
  ACC="ACC$i"
  BATCH_ID=$(printf "%02d" $(( (i - START) / 25 + 1 )))  # Batches: 25 items each
  echo "Inserting $ID / $ACC"

  aws dynamodb put-item \
    --table-name "$TABLE" \
    --item "{
      \"ID\": {\"S\": \"$ID\"},
      \"ACCOUNTNUMBER\": {\"S\": \"$ACC\"},
      \"BatchId\": {\"S\": \"01\"},
      \"PclmType\": {\"S\": \"PCLD\"}
    }" \
    --output text >/dev/null
done

echo "✅ Inserted 200 items from ID20 to ID219 into $TABLE"
