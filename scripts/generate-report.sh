#!/bin/bash

set -euo pipefail

source /root/lab.env

STUDENT_COUNT=${student_count:-5}
STUDENT_WEB_PORT_START=${student_web_port_start:-8001}
STUDENT_APP_PORT_START=${student_app_port_start:-9001}
ENABLE_STUDENT_WEB_ACCESS=${enable_student_web_access:-true}
ENABLE_STUDENT_APP_PORT_ACCESS=${enable_student_app_port_access:-true}
ENABLE_ADMIN_DASHBOARD=${enable_admin_dashboard:-true}
ADMIN_DASHBOARD_PORT=${admin_dashboard_port:-8080}
LAB_ROOT=${lab_data_mount_point:-/lab-data}
DATA_DIR=/opt/cloud-lab/dashboard/data
REPORT_DIR=/opt/cloud-lab/reports
BACKUP_ROOT="$LAB_ROOT/backups"

mkdir -p "$DATA_DIR" "$REPORT_DIR"

PUBLIC_IP=$(curl -fsS http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "pending")
HOSTNAME=$(hostname)
LAST_BACKUP=$(find "$BACKUP_ROOT" -maxdepth 1 -type f -name 'lab-backup-*.tar.gz' 2>/dev/null | sort | tail -n 1)
BACKUP_COUNT=$(find "$BACKUP_ROOT" -maxdepth 1 -type f -name 'lab-backup-*.tar.gz' 2>/dev/null | wc -l | tr -d ' ')

jq -n \
  --arg generated_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --arg public_ip "$PUBLIC_IP" \
  --arg hostname "$HOSTNAME" \
  --arg dashboard_url "$( [[ "$ENABLE_ADMIN_DASHBOARD" == "true" ]] && printf 'http://%s:%s' "$PUBLIC_IP" "$ADMIN_DASHBOARD_PORT" )" \
  --arg last_backup "${LAST_BACKUP:-}" \
  --arg backup_count "${BACKUP_COUNT:-0}" \
  --arg web_enabled "$ENABLE_STUDENT_WEB_ACCESS" \
  --arg app_enabled "$ENABLE_STUDENT_APP_PORT_ACCESS" \
  --arg web_start "$STUDENT_WEB_PORT_START" \
  --arg app_start "$STUDENT_APP_PORT_START" \
  --argjson student_count "$STUDENT_COUNT" \
  '{
    generated_at: $generated_at,
    public_ip: $public_ip,
    hostname: $hostname,
    dashboard_url: $dashboard_url,
    backups: {
      last_backup: $last_backup,
      backup_count: ($backup_count | tonumber)
    },
    students: [
      range(1; $student_count + 1) as $i
      | {
          student_id: ("student" + ($i | tostring)),
          ssh_port: (2200 + $i),
          static_url: (if $web_enabled == "true" then ("http://" + $public_ip + ":" + (($web_start | tonumber) + $i - 1 | tostring)) else "" end),
          dynamic_url: (if $app_enabled == "true" then ("http://" + $public_ip + ":" + (($app_start | tonumber) + $i - 1 | tostring)) else "" end)
        }
    ]
  }' > "$DATA_DIR/report.json"

{
  echo "Cloud Lab Admin Report"
  echo "Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "Host: $HOSTNAME"
  echo "Public IP: $PUBLIC_IP"
  if [[ "$ENABLE_ADMIN_DASHBOARD" == "true" ]]; then
    echo "Dashboard: http://$PUBLIC_IP:$ADMIN_DASHBOARD_PORT"
  fi
  echo "Students: $STUDENT_COUNT"
  echo "Backups kept: ${BACKUP_COUNT:-0}"
  echo
  for i in $(seq 1 "$STUDENT_COUNT"); do
    echo "student$i"
    echo "  SSH: ssh -p $((2200 + i)) student@$PUBLIC_IP"
    if [[ "$ENABLE_STUDENT_WEB_ACCESS" == "true" ]]; then
      echo "  Static: http://$PUBLIC_IP:$((STUDENT_WEB_PORT_START + i - 1))"
    fi
    if [[ "$ENABLE_STUDENT_APP_PORT_ACCESS" == "true" ]]; then
      echo "  Dynamic: http://$PUBLIC_IP:$((STUDENT_APP_PORT_START + i - 1))"
    fi
  done
} > "$REPORT_DIR/admin-report.txt"
