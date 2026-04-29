#!/bin/bash

set -euo pipefail

source /root/lab.env

STUDENT_COUNT=${student_count:-5}
ACTION=${1:-}

if [[ "$ACTION" != "open" && "$ACTION" != "close" ]]; then
  echo "Usage: $0 open|close"
  exit 1
fi

for i in $(seq 1 "$STUDENT_COUNT"); do
  student="student$i"
  if docker container inspect "$student" >/dev/null 2>&1; then
    if [[ "$ACTION" == "open" ]]; then
      docker start "$student" >/dev/null 2>&1 || true
    else
      docker stop "$student" >/dev/null 2>&1 || true
    fi
  fi
done

/opt/cloud-lab/collect-usage.sh >/dev/null 2>&1 || true
/opt/cloud-lab/generate-report.sh >/dev/null 2>&1 || true
/opt/cloud-lab/render-dashboard.sh >/dev/null 2>&1 || true
