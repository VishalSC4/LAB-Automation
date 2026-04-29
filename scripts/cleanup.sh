#!/bin/bash

set -euo pipefail

source /root/lab.env

ENABLE_AUTO_CLEANUP=${enable_auto_cleanup:-true}
LAB_ROOT=${lab_data_mount_point:-/lab-data}

if [[ "$ENABLE_AUTO_CLEANUP" != "true" ]]; then
  exit 0
fi

docker image prune -af >/dev/null 2>&1 || true
find /var/log -type f -name '*.log' -size +100M -exec truncate -s 0 {} \; 2>/dev/null || true
find "$LAB_ROOT" -type f -name '*.tmp' -mtime +7 -delete 2>/dev/null || true
find /tmp -mindepth 1 -mtime +3 -delete 2>/dev/null || true

/opt/cloud-lab/generate-report.sh >/dev/null 2>&1 || true
/opt/cloud-lab/render-dashboard.sh >/dev/null 2>&1 || true
