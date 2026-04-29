#!/bin/bash
set -xe

exec > /var/log/user-data.log 2>&1

echo "===== USER DATA START ====="

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y docker.io jq curl awscli git rsync python3 python3-venv

LAB_DATA_MOUNT_POINT="${lab_data_mount_point}"

wait_for_data_disk() {
  local root_disk
  local candidate

  root_disk=$(lsblk -ndo PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null || true)

  for _ in $(seq 1 150); do
    candidate=$(lsblk -dpno NAME,TYPE | awk -v root="$root_disk" '$2 == "disk" && (root == "" || index($1, root) == 0) { print $1; exit }')
    if [[ -n "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
    sleep 2
  done

  return 1
}

DATA_DEVICE=$(wait_for_data_disk || true)
mkdir -p "$LAB_DATA_MOUNT_POINT"
DOCKER_DATA_ROOT="/var/lib/docker"

if [[ -n "$${DATA_DEVICE:-}" ]]; then
  if ! blkid "$DATA_DEVICE" >/dev/null 2>&1; then
    mkfs.ext4 -F -L cloud-lab-data "$DATA_DEVICE"
  fi

  DATA_UUID=$(blkid -s UUID -o value "$DATA_DEVICE")
  grep -q "$DATA_UUID" /etc/fstab || echo "UUID=$DATA_UUID $LAB_DATA_MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
  mountpoint -q "$LAB_DATA_MOUNT_POINT" || mount "$LAB_DATA_MOUNT_POINT"
  DOCKER_DATA_ROOT="$LAB_DATA_MOUNT_POINT/docker"
else
  echo "Persistent lab data disk not found during bootstrap. Continuing with root volume storage."
fi

mkdir -p /etc/docker
mkdir -p "$DOCKER_DATA_ROOT"
cat <<EOF > /etc/docker/daemon.json
{
  "data-root": "$DOCKER_DATA_ROOT"
}
EOF

systemctl enable docker
systemctl restart docker

mkdir -p /opt/cloud-lab "$LAB_DATA_MOUNT_POINT"

cat <<'CREDENTIALS' > /root/credentials.json
${credentials_json}
CREDENTIALS

chmod 600 /root/credentials.json

cat <<ENV > /root/lab.env
aws_region="${aws_region}"
student_count="${student_count}"
container_memory="${container_memory}"
container_cpu="${container_cpu}"
sync_interval_minutes="${sync_interval_minutes}"
student_web_port_start="${student_web_port_start}"
student_app_port_start="${student_app_port_start}"
enable_student_web_access="${enable_student_web_access}"
enable_student_app_port_access="${enable_student_app_port_access}"
enable_github_sync="${enable_github_sync}"
enable_container_state_restore="${enable_container_state_restore}"
enable_repo_bootstrap="${enable_repo_bootstrap}"
github_org="${github_org}"
github_repo_prefix="${github_repo_prefix}"
github_repository_url="${github_repository_url}"
github_branch="${github_branch}"
github_student_branch_prefix="${github_student_branch_prefix}"
github_token_ssm_parameter="${github_token_ssm_parameter}"
github_commit_author_name="${github_commit_author_name}"
github_commit_author_email="${github_commit_author_email}"
enable_admin_dashboard="${enable_admin_dashboard}"
admin_dashboard_port="${admin_dashboard_port}"
enable_backups="${enable_backups}"
backup_interval_minutes="${backup_interval_minutes}"
backup_retention_count="${backup_retention_count}"
enable_usage_tracking="${enable_usage_tracking}"
usage_tracking_interval_minutes="${usage_tracking_interval_minutes}"
enable_auto_cleanup="${enable_auto_cleanup}"
cleanup_interval_hours="${cleanup_interval_hours}"
enable_lab_schedule="${enable_lab_schedule}"
lab_open_time="${lab_open_time}"
lab_close_time="${lab_close_time}"
lab_timezone="${lab_timezone}"
enable_email_alerts="${enable_email_alerts}"
alert_email_from="${alert_email_from}"
alert_email_to="${alert_email_to}"
lab_data_mount_point="${lab_data_mount_point}"
ENV

mkdir -p /root/.aws /home/ubuntu/.aws
cat <<EOF > /root/.aws/config
[default]
region = ${aws_region}
EOF
cp /root/.aws/config /home/ubuntu/.aws/config
chown -R ubuntu:ubuntu /home/ubuntu/.aws

cat <<'SETUP' > /opt/cloud-lab/setup.sh
${setup_script}
SETUP

cat <<'SYNC' > /opt/cloud-lab/sync-data.sh
${sync_script}
SYNC

cat <<'BACKUP' > /opt/cloud-lab/backup-data.sh
${backup_script}
BACKUP

cat <<'CLEANUP' > /opt/cloud-lab/cleanup.sh
${cleanup_script}
CLEANUP

cat <<'USAGE' > /opt/cloud-lab/collect-usage.sh
${usage_script}
USAGE

cat <<'REPORT' > /opt/cloud-lab/generate-report.sh
${report_script}
REPORT

cat <<'DASHBOARD' > /opt/cloud-lab/render-dashboard.sh
${dashboard_script}
DASHBOARD

cat <<'ALERT' > /opt/cloud-lab/send-alert.sh
${alert_script}
ALERT

cat <<'RESET' > /opt/cloud-lab/reset-student-password.sh
${reset_password_script}
RESET

cat <<'SCHEDULE' > /opt/cloud-lab/toggle-lab-access.sh
${schedule_script}
SCHEDULE

chmod +x /opt/cloud-lab/setup.sh /opt/cloud-lab/sync-data.sh /opt/cloud-lab/backup-data.sh /opt/cloud-lab/cleanup.sh /opt/cloud-lab/collect-usage.sh /opt/cloud-lab/generate-report.sh /opt/cloud-lab/render-dashboard.sh /opt/cloud-lab/send-alert.sh /opt/cloud-lab/reset-student-password.sh /opt/cloud-lab/toggle-lab-access.sh

cat <<'SERVICE' > /etc/systemd/system/lab-setup.service
[Unit]
Description=Cloud Lab Setup
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/bin/bash /opt/cloud-lab/setup.sh
RemainAfterExit=true
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
SERVICE

cat <<'SYNC_SERVICE' > /etc/systemd/system/lab-sync.service
[Unit]
Description=Sync cloud lab student data to GitHub
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash /opt/cloud-lab/sync-data.sh
SYNC_SERVICE

cat <<'BACKUP_SERVICE' > /etc/systemd/system/lab-backup.service
[Unit]
Description=Backup cloud lab data
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash /opt/cloud-lab/backup-data.sh
BACKUP_SERVICE

cat <<'USAGE_SERVICE' > /etc/systemd/system/lab-usage.service
[Unit]
Description=Collect cloud lab usage metrics
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash /opt/cloud-lab/collect-usage.sh
USAGE_SERVICE

cat <<'REPORT_SERVICE' > /etc/systemd/system/lab-report.service
[Unit]
Description=Generate cloud lab report
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash /opt/cloud-lab/generate-report.sh

[Install]
WantedBy=multi-user.target
REPORT_SERVICE

cat <<'CLEANUP_SERVICE' > /etc/systemd/system/lab-cleanup.service
[Unit]
Description=Cleanup cloud lab host
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash /opt/cloud-lab/cleanup.sh
CLEANUP_SERVICE

cat <<'DASHBOARD_SERVICE' > /etc/systemd/system/lab-dashboard.service
[Unit]
Description=Cloud lab admin dashboard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/cloud-lab/dashboard
ExecStart=/usr/bin/python3 -m http.server ${admin_dashboard_port} --directory /opt/cloud-lab/dashboard
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
DASHBOARD_SERVICE

cat <<'LAB_OPEN_SERVICE' > /etc/systemd/system/lab-open.service
[Unit]
Description=Open the lab for students
After=docker.service network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash /opt/cloud-lab/toggle-lab-access.sh open
LAB_OPEN_SERVICE

cat <<'LAB_CLOSE_SERVICE' > /etc/systemd/system/lab-close.service
[Unit]
Description=Close the lab for students
After=docker.service network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash /opt/cloud-lab/toggle-lab-access.sh close
LAB_CLOSE_SERVICE

cat <<TIMER > /etc/systemd/system/lab-sync.timer
[Unit]
Description=Periodic sync of cloud lab student data to GitHub

[Timer]
OnBootSec=3min
OnUnitActiveSec=${sync_interval_minutes}min
Persistent=true

[Install]
WantedBy=timers.target
TIMER

cat <<BACKUP_TIMER > /etc/systemd/system/lab-backup.timer
[Unit]
Description=Periodic cloud lab backups

[Timer]
OnBootSec=5min
OnUnitActiveSec=${backup_interval_minutes}min
Persistent=true

[Install]
WantedBy=timers.target
BACKUP_TIMER

cat <<USAGE_TIMER > /etc/systemd/system/lab-usage.timer
[Unit]
Description=Periodic cloud lab usage collection

[Timer]
OnBootSec=4min
OnUnitActiveSec=${usage_tracking_interval_minutes}min
Persistent=true

[Install]
WantedBy=timers.target
USAGE_TIMER

cat <<CLEANUP_TIMER > /etc/systemd/system/lab-cleanup.timer
[Unit]
Description=Periodic cloud lab cleanup

[Timer]
OnBootSec=10min
OnUnitActiveSec=${cleanup_interval_hours}h
Persistent=true

[Install]
WantedBy=timers.target
CLEANUP_TIMER

cat <<LAB_OPEN_TIMER > /etc/systemd/system/lab-open.timer
[Unit]
Description=Daily lab open timer

[Timer]
OnCalendar=*-*-* ${lab_open_time}:00
Timezone=${lab_timezone}
Persistent=true

[Install]
WantedBy=timers.target
LAB_OPEN_TIMER

cat <<LAB_CLOSE_TIMER > /etc/systemd/system/lab-close.timer
[Unit]
Description=Daily lab close timer

[Timer]
OnCalendar=*-*-* ${lab_close_time}:00
Timezone=${lab_timezone}
Persistent=true

[Install]
WantedBy=timers.target
LAB_CLOSE_TIMER

cat <<'STOP_SERVICE' > /etc/systemd/system/lab-sync-on-shutdown.service
[Unit]
Description=Sync cloud lab data to GitHub during shutdown
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
ExecStart=/bin/bash /opt/cloud-lab/sync-data.sh
TimeoutStartSec=0

[Install]
WantedBy=halt.target reboot.target shutdown.target
STOP_SERVICE

systemctl daemon-reload
systemctl enable lab-setup.service
systemctl enable lab-sync.timer
systemctl enable lab-sync-on-shutdown.service
systemctl enable lab-report.service
if [[ "${enable_admin_dashboard}" == "true" ]]; then systemctl enable lab-dashboard.service; fi
if [[ "${enable_backups}" == "true" ]]; then systemctl enable lab-backup.timer; fi
if [[ "${enable_usage_tracking}" == "true" ]]; then systemctl enable lab-usage.timer; fi
if [[ "${enable_auto_cleanup}" == "true" ]]; then systemctl enable lab-cleanup.timer; fi
if [[ "${enable_lab_schedule}" == "true" ]]; then
  systemctl enable lab-open.timer
  systemctl enable lab-close.timer
fi
systemctl start lab-setup.service || true
systemctl start lab-sync.timer || true
systemctl start lab-report.service || true
if [[ "${enable_admin_dashboard}" == "true" ]]; then systemctl start lab-dashboard.service || true; fi
if [[ "${enable_backups}" == "true" ]]; then systemctl start lab-backup.timer || true; fi
if [[ "${enable_usage_tracking}" == "true" ]]; then systemctl start lab-usage.timer || true; fi
if [[ "${enable_auto_cleanup}" == "true" ]]; then systemctl start lab-cleanup.timer || true; fi
if [[ "${enable_lab_schedule}" == "true" ]]; then
  systemctl start lab-open.timer || true
  systemctl start lab-close.timer || true
fi

echo "===== USER DATA END ====="
