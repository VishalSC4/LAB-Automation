#!/bin/bash

set -euo pipefail

source /root/lab.env

ENABLE_EMAIL_ALERTS=${enable_email_alerts:-false}
ALERT_EMAIL_FROM=${alert_email_from:-}
ALERT_EMAIL_TO=${alert_email_to:-}
AWS_REGION=${aws_region:-ap-south-1}

SUBJECT=${1:-"Cloud Lab Alert"}
BODY=${2:-"Cloud Lab notification"}

if [[ "$ENABLE_EMAIL_ALERTS" != "true" ]]; then
  exit 0
fi

if [[ -z "$ALERT_EMAIL_FROM" || -z "$ALERT_EMAIL_TO" ]]; then
  exit 0
fi

aws ses send-email \
  --region "$AWS_REGION" \
  --from "$ALERT_EMAIL_FROM" \
  --destination "ToAddresses=$ALERT_EMAIL_TO" \
  --message "Subject={Data=\"$SUBJECT\"},Body={Text={Data=\"$BODY\"}}" \
  >/dev/null
