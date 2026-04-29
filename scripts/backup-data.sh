#!/bin/bash

set -euo pipefail

source /root/lab.env

ENABLE_BACKUPS=${enable_backups:-true}
BACKUP_RETENTION_COUNT=${backup_retention_count:-24}
LAB_ROOT=${lab_data_mount_point:-/lab-data}
BACKUP_ROOT="$LAB_ROOT/backups"

if [[ "$ENABLE_BACKUPS" != "true" ]]; then
  exit 0
fi

mkdir -p "$BACKUP_ROOT"

STAMP=$(date -u '+%Y%m%d-%H%M%S')
TARGET="$BACKUP_ROOT/lab-backup-$STAMP.tar.gz"

tar \
  --exclude="$BACKUP_ROOT" \
  --exclude="$LAB_ROOT/docker" \
  --exclude="$LAB_ROOT/*/state-repo/.git" \
  --exclude="$LAB_ROOT/*/state-repo/.git/*" \
  -czf "$TARGET" \
  "$LAB_ROOT"

mapfile -t backups < <(find "$BACKUP_ROOT" -maxdepth 1 -type f -name 'lab-backup-*.tar.gz' | sort)

if (( ${#backups[@]} > BACKUP_RETENTION_COUNT )); then
  remove_count=$(( ${#backups[@]} - BACKUP_RETENTION_COUNT ))
  for old_backup in "${backups[@]:0:remove_count}"; do
    rm -f "$old_backup"
  done
fi

/opt/cloud-lab/generate-report.sh >/dev/null 2>&1 || true
/opt/cloud-lab/render-dashboard.sh >/dev/null 2>&1 || true
