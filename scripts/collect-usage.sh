#!/bin/bash

set -euo pipefail

source /root/lab.env

ENABLE_USAGE_TRACKING=${enable_usage_tracking:-true}
STUDENT_COUNT=${student_count:-5}
LAB_ROOT=${lab_data_mount_point:-/lab-data}
DATA_DIR=/opt/cloud-lab/dashboard/data

if [[ "$ENABLE_USAGE_TRACKING" != "true" ]]; then
  exit 0
fi

mkdir -p "$DATA_DIR"

TMP_FILE=$(mktemp)

{
  echo '['
  first=true
  for i in $(seq 1 "$STUDENT_COUNT"); do
    student="student$i"
    inspect=$(docker inspect "$student" 2>/dev/null | jq '.[0]' 2>/dev/null || true)
    stats_line=$(docker stats "$student" --no-stream --format '{{json .}}' 2>/dev/null || true)
    [[ -z "$inspect" ]] && continue

    status=$(echo "$inspect" | jq -r '.State.Status // "missing"')
    started_at=$(echo "$inspect" | jq -r '.State.StartedAt // ""')
    cpu_percent=$(echo "$stats_line" | jq -r '.CPUPerc // "0%"' 2>/dev/null || echo "0%")
    mem_usage=$(echo "$stats_line" | jq -r '.MemUsage // "0B / 0B"' 2>/dev/null || echo "0B / 0B")

    if [[ "$first" == "true" ]]; then
      first=false
    else
      echo ','
    fi

    jq -n \
      --arg student_id "$student" \
      --arg status "$status" \
      --arg started_at "$started_at" \
      --arg cpu_percent "$cpu_percent" \
      --arg memory_usage "$mem_usage" \
      '{
        student_id: $student_id,
        status: $status,
        started_at: $started_at,
        cpu_percent: $cpu_percent,
        memory_usage: $memory_usage
      }'
  done
  echo ']'
} > "$TMP_FILE"

jq . "$TMP_FILE" > "$DATA_DIR/usage.json"
rm -f "$TMP_FILE"
