#!/bin/bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 student1 [new-password]"
  exit 1
fi

STUDENT="$1"
if [[ $# -ge 2 ]]; then
  NEW_PASSWORD="$2"
else
  NEW_PASSWORD="Lab$(openssl rand -hex 8 | cut -c1-8)@1"
fi

if ! docker container inspect "$STUDENT" >/dev/null 2>&1; then
  echo "Container $STUDENT not found."
  exit 1
fi

docker exec -e STUDENT_PASSWORD="$NEW_PASSWORD" "$STUDENT" bash -lc 'printf "%s:%s\n" "student" "$STUDENT_PASSWORD" | chpasswd'

echo "Password reset complete for $STUDENT"
echo "New password: $NEW_PASSWORD"
