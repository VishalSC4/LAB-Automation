#!/bin/bash

set -euo pipefail

exec > /var/log/lab-setup.log 2>&1

source /root/lab.env

AWS_REGION=${aws_region:-ap-south-1}
export AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

STUDENT_COUNT=${student_count:-5}
CONTAINER_MEMORY=${container_memory:-256m}
CONTAINER_CPU=${container_cpu:-0.20}
STUDENT_WEB_PORT_START=${student_web_port_start:-8001}
STUDENT_APP_PORT_START=${student_app_port_start:-9001}
ENABLE_STUDENT_WEB_ACCESS=${enable_student_web_access:-true}
ENABLE_STUDENT_APP_PORT_ACCESS=${enable_student_app_port_access:-true}
ENABLE_GITHUB_SYNC=${enable_github_sync:-false}
ENABLE_CONTAINER_STATE_RESTORE=${enable_container_state_restore:-false}
ENABLE_REPO_BOOTSTRAP=${enable_repo_bootstrap:-false}
ENABLE_ADMIN_DASHBOARD=${enable_admin_dashboard:-true}
ENABLE_EMAIL_ALERTS=${enable_email_alerts:-false}
GITHUB_ORG=${github_org:-}
GITHUB_REPO_PREFIX=${github_repo_prefix:-student-lab}
GITHUB_REPOSITORY_URL=${github_repository_url:-}
GITHUB_BRANCH=${github_branch:-main}
GITHUB_STUDENT_BRANCH_PREFIX=${github_student_branch_prefix:-student-}
GITHUB_TOKEN_SSM_PARAMETER=${github_token_ssm_parameter:-}
GIT_AUTHOR_NAME=${github_commit_author_name:-Cloud Lab Bot}
GIT_AUTHOR_EMAIL=${github_commit_author_email:-cloud-lab-bot@example.com}
LAB_ROOT=${lab_data_mount_point:-/lab-data}
CREDENTIALS_JSON=$(cat /root/credentials.json)
GIT_TOKEN=""
GITHUB_SYNC_ACTIVE=false
HOST_MARKER_FILE="$LAB_ROOT/.lab-host-instance-id"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

build_student_image_if_needed() {
  local dockerfile_hash_file="$LAB_ROOT/.student-lab-image.hash"
  local current_hash=""
  local previous_hash=""

  current_hash=$(cat Dockerfile start-services.sh | sha256sum | awk '{print $1}')
  previous_hash=$(cat "$dockerfile_hash_file" 2>/dev/null || true)

  if [[ "$previous_hash" == "$current_hash" ]] && docker image inspect student-lab:latest >/dev/null 2>&1; then
    log "student-lab:latest already matches the current bootstrap definition. Skipping rebuild."
    return
  fi

  log "Building student-lab container image..."
  if ! retry 3 env DOCKER_BUILDKIT=0 docker build -t student-lab:latest .; then
    fail "Failed to build student-lab:latest image."
  fi
  docker image inspect student-lab:latest >/dev/null 2>&1 || fail "student-lab:latest image was not created successfully."
  printf '%s\n' "$current_hash" > "$dockerfile_hash_file"
  log "Student-lab image build completed."
}

retry() {
  local attempts="$1"
  shift

  local attempt=1
  until "$@"; do
    if (( attempt >= attempts )); then
      return 1
    fi

    log "Attempt $attempt failed for: $*. Retrying..."
    attempt=$((attempt + 1))
    sleep 10
  done
}

alert() {
  local subject="$1"
  local body="$2"

  if [[ -x /opt/cloud-lab/send-alert.sh ]]; then
    /opt/cloud-lab/send-alert.sh "$subject" "$body" || true
  fi
}

fail() {
  local message="$1"
  log "ERROR: $message"
  alert "Cloud Lab setup failed" "$message"
  exit 1
}

resolve_repo_and_branch() {
  local student_index="$1"

  if [[ -n "$GITHUB_REPOSITORY_URL" ]]; then
    RESOLVED_REPO_URL="$GITHUB_REPOSITORY_URL"
    RESOLVED_BRANCH="${GITHUB_STUDENT_BRANCH_PREFIX}${student_index}"
    return
  fi

  if [[ -z "$GITHUB_ORG" ]]; then
    fail "Set github_repository_url or github_org before enabling GitHub sync."
  fi

  local repo_name="${GITHUB_REPO_PREFIX}-${student_index}"
  RESOLVED_REPO_URL="https://github.com/$GITHUB_ORG/$repo_name.git"
  RESOLVED_BRANCH="$GITHUB_BRANCH"
}

github_api() {
  local method="$1"
  local endpoint="$2"
  local body="${3:-}"

  if [[ -z "$GIT_TOKEN" ]]; then
    return 1
  fi

  local args=(
    --silent
    --show-error
    --fail
    -X "$method"
    -H "Accept: application/vnd.github+json"
    -H "Authorization: Bearer $GIT_TOKEN"
    "https://api.github.com$endpoint"
  )

  if [[ -n "$body" ]]; then
    args+=(-d "$body")
  fi

  curl "${args[@]}"
}

get_repo_default_branch() {
  local repo_name="$1"
  local default_branch=""

  default_branch=$(github_api GET "/repos/$GITHUB_ORG/$repo_name" 2>/dev/null | jq -r '.default_branch // empty' 2>/dev/null || true)
  if [[ -n "$default_branch" ]]; then
    echo "$default_branch"
  fi
}

ensure_repo_branch_exists() {
  local repo_name="$1"
  local branch_name="$2"
  local source_branch="$3"

  if github_api GET "/repos/$GITHUB_ORG/$repo_name/git/ref/heads/$branch_name" >/dev/null 2>&1; then
    return
  fi

  local base_sha=""
  base_sha=$(github_api GET "/repos/$GITHUB_ORG/$repo_name/git/ref/heads/$source_branch" 2>/dev/null | jq -r '.object.sha // empty')
  if [[ -n "$base_sha" ]]; then
    github_api POST "/repos/$GITHUB_ORG/$repo_name/git/refs" "{\"ref\":\"refs/heads/$branch_name\",\"sha\":\"$base_sha\"}" >/dev/null 2>&1 || true
  fi
}

ensure_repo_default_branch() {
  local repo_name="$1"
  local branch_name="$2"
  local current_default_branch=""

  current_default_branch=$(get_repo_default_branch "$repo_name")
  if [[ -z "$current_default_branch" ]]; then
    current_default_branch="$branch_name"
  fi

  if [[ "$branch_name" != "$current_default_branch" ]]; then
    ensure_repo_branch_exists "$repo_name" "$branch_name" "$current_default_branch"
    set_repo_default_branch "$repo_name" "$branch_name"
  fi
}

set_repo_default_branch() {
  local repo_name="$1"
  local branch_name="$2"

  github_api PATCH "/repos/$GITHUB_ORG/$repo_name" "{\"default_branch\":\"$branch_name\"}" >/dev/null 2>&1 || true
}

load_github_token() {
  if [[ "$ENABLE_GITHUB_SYNC" != "true" ]]; then
    return
  fi

  if [[ -z "$GITHUB_TOKEN_SSM_PARAMETER" ]]; then
    log "GitHub sync is enabled but github_token_ssm_parameter is empty."
    return
  fi

  GIT_TOKEN=$(aws ssm get-parameter \
    --region "$AWS_REGION" \
    --name "$GITHUB_TOKEN_SSM_PARAMETER" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text) || {
      log "Could not read GitHub token from SSM."
      return
    }

  if [[ -z "$GIT_TOKEN" || "$GIT_TOKEN" == "None" ]]; then
    log "GitHub token in SSM is empty."
    return
  fi

  export GIT_TOKEN
  cat <<'EOF' > /root/.lab-git-askpass
#!/bin/bash
echo "${GIT_TOKEN}"
EOF
  chmod 700 /root/.lab-git-askpass
  GITHUB_SYNC_ACTIVE=true
}

bootstrap_repo_if_needed() {
  local student_index="$1"
  local repo_url="$2"
  local branch_name="$3"

  if [[ "$ENABLE_GITHUB_SYNC" != "true" || "$ENABLE_REPO_BOOTSTRAP" != "true" || "$GITHUB_SYNC_ACTIVE" != "true" ]]; then
    return
  fi

  if [[ -n "$GITHUB_REPOSITORY_URL" ]]; then
    if ! git ls-remote --exit-code --heads "$repo_url" "$branch_name" >/dev/null 2>&1; then
      local temp_dir
      temp_dir=$(mktemp -d)
      git -C "$temp_dir" init -b "$branch_name" >/dev/null 2>&1
      cat <<EOF > "$temp_dir/README.md"
# Student ${student_index} Lab State

This branch is managed by Cloud Lab automation.
EOF
      git -C "$temp_dir" config user.name "$GIT_AUTHOR_NAME"
      git -C "$temp_dir" config user.email "$GIT_AUTHOR_EMAIL"
      git -C "$temp_dir" add README.md
      git -C "$temp_dir" commit -m "Initialize ${branch_name}" >/dev/null 2>&1 || true
      git -C "$temp_dir" remote add origin "$repo_url"
      GIT_ASKPASS=/root/.lab-git-askpass GIT_TERMINAL_PROMPT=0 git -C "$temp_dir" push -u origin "$branch_name" >/dev/null 2>&1 || true
      rm -rf "$temp_dir"
    fi
    return
  fi

  local repo_name="${GITHUB_REPO_PREFIX}-${student_index}"
  if ! github_api GET "/repos/$GITHUB_ORG/$repo_name" >/dev/null 2>&1; then
    github_api POST "/orgs/$GITHUB_ORG/repos" "{\"name\":\"$repo_name\",\"private\":true,\"auto_init\":true}" >/dev/null 2>&1 || \
    github_api POST "/user/repos" "{\"name\":\"$repo_name\",\"private\":true,\"auto_init\":true}" >/dev/null 2>&1 || true
  fi

  ensure_repo_default_branch "$repo_name" "$branch_name"
}

sync_dir_from_repo() {
  local repo_subdir="$1"
  local target_dir="$2"

  mkdir -p "$target_dir"
  if [[ -d "$repo_subdir" ]]; then
    rsync -a --delete "$repo_subdir"/ "$target_dir"/
  fi
}

should_skip_container_path() {
  local path="$1"

  case "$path" in
    /dev|/dev/*|/proc|/proc/*|/sys|/sys/*|/run|/run/*|/tmp|/tmp/*|/mnt|/mnt/*|/media|/media/*)
      return 0
      ;;
    /var/tmp|/var/tmp/*|/var/run|/var/run/*)
      return 0
      ;;
    /var/log|/var/log/*|/var/cache/apt|/var/cache/apt/*|/var/lib/apt/lists|/var/lib/apt/lists/*|/var/lib/dpkg/lock|/var/lib/dpkg/lock-*|/var/lib/systemd|/var/lib/systemd/*)
      return 0
      ;;
    /home/student|/home/student/*|/var/www/html|/var/www/html/*)
      return 0
      ;;
    /usr/local/bin/start-services.sh|/etc/ssh/ssh_host_*|/etc/machine-id)
      return 0
      ;;
    /etc/hostname|/etc/hosts|/etc/resolv.conf|/.dockerenv)
      return 0
      ;;
  esac

  return 1
}

detect_host_identity() {
  local instance_id

  instance_id=$(curl -fsS --max-time 2 http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || true)
  if [[ -n "$instance_id" ]]; then
    echo "$instance_id"
    return
  fi

  hostname
}

reset_runtime_after_host_change() {
  local current_host_id="$1"
  local previous_host_id=""

  if [[ -f "$HOST_MARKER_FILE" ]]; then
    previous_host_id=$(cat "$HOST_MARKER_FILE" 2>/dev/null || true)
  fi

  if [[ -n "$previous_host_id" && "$previous_host_id" != "$current_host_id" ]]; then
    log "Detected host change from $previous_host_id to $current_host_id. Resetting stale Docker student runtime."
    for i in $(seq 1 "$STUDENT_COUNT"); do
      remove_container_if_exists "student$i"
    done
    docker network rm student-network >/dev/null 2>&1 || true
  fi

  printf '%s\n' "$current_host_id" > "$HOST_MARKER_FILE"
}

restore_container_diff() {
  if [[ "$ENABLE_CONTAINER_STATE_RESTORE" != "true" ]]; then
    return
  fi

  local student="$1"
  local repo_dir="$2"
  local diff_root="$repo_dir/container-diff"
  local files_dir="$diff_root/files"
  local deletions_file="$diff_root/deletions.txt"

  if [[ ! -d "$files_dir" && ! -f "$deletions_file" ]]; then
    return
  fi

  docker stop "$student" >/dev/null 2>&1 || true

  if [[ -d "$files_dir" ]] && [[ -n "$(find "$files_dir" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
    tar -C "$files_dir" -cf - . | docker cp - "$student:/" || {
      log "Container diff file restore failed for $student."
      return 1
    }
  fi

  if ! docker start "$student" >/dev/null 2>&1; then
    capture_container_debug_info "$student"
    log "Could not restart container $student after restore."
    return 1
  fi
  sleep 2

  if ! container_is_running "$student"; then
    capture_container_debug_info "$student"
    log "Container $student stopped immediately after restore."
    return 1
  fi

  if [[ -f "$deletions_file" ]]; then
    while IFS= read -r deleted_path; do
      [[ -z "$deleted_path" ]] && continue
      should_skip_container_path "$deleted_path" && continue
      docker exec "$student" sh -lc "rm -rf -- \"\$1\"" _ "$deleted_path" >/dev/null 2>&1 || true
    done < "$deletions_file"
  fi

  if ! container_is_running "$student"; then
    capture_container_debug_info "$student"
    log "Container $student stopped after applying restore deletions."
    return 1
  fi
}

ensure_student_repo() {
  local student_index="$1"
  local student_name="$2"
  local repo_dir="$3"
  local home_dir="$4"
  local www_dir="$5"

  resolve_repo_and_branch "$student_index"
  local repo_url="$RESOLVED_REPO_URL"
  local target_branch="$RESOLVED_BRANCH"

  bootstrap_repo_if_needed "$student_index" "$repo_url" "$target_branch"

  mkdir -p "$repo_dir"

  export GIT_ASKPASS=/root/.lab-git-askpass
  export GIT_TERMINAL_PROMPT=0

  if [[ ! -d "$repo_dir/.git" ]]; then
    rm -rf "$repo_dir"
    mkdir -p "$repo_dir"
    git -C "$repo_dir" init -b "$target_branch" >/dev/null 2>&1
    git -C "$repo_dir" remote add origin "$repo_url" || true
  fi

  git -C "$repo_dir" config user.name "$GIT_AUTHOR_NAME"
  git -C "$repo_dir" config user.email "$GIT_AUTHOR_EMAIL"
  git -C "$repo_dir" remote set-url origin "$repo_url" || true
  git -C "$repo_dir" fetch origin --prune || true
  git -C "$repo_dir" checkout -B "$target_branch" >/dev/null 2>&1 || true

  if git ls-remote --exit-code --heads "$repo_url" "$target_branch" >/dev/null 2>&1; then
    git -C "$repo_dir" reset --hard "origin/$target_branch" >/dev/null 2>&1 || true
  elif [[ ! -f "$repo_dir/README.md" ]]; then
    mkdir -p "$repo_dir/home" "$repo_dir/www"
    cat <<EOF > "$repo_dir/README.md"
# ${student_name^} Lab State

This branch is managed by Cloud Lab automation.
EOF
    git -C "$repo_dir" add README.md home www
    git -C "$repo_dir" commit -m "Initialize student state" >/dev/null 2>&1 || true
  fi

  sync_dir_from_repo "$repo_dir/home" "$home_dir"
  sync_dir_from_repo "$repo_dir/www" "$www_dir"
}

restore_from_github() {
  if [[ "$ENABLE_GITHUB_SYNC" != "true" || "$GITHUB_SYNC_ACTIVE" != "true" ]]; then
    return
  fi

  for i in $(seq 1 "$STUDENT_COUNT"); do
    local student_name="student$i"
    local home_dir="$LAB_ROOT/$student_name/home"
    local www_dir="$LAB_ROOT/$student_name/www"
    local repo_dir="$LAB_ROOT/$student_name/state-repo"

    mkdir -p "$home_dir" "$www_dir"
    ensure_student_repo "$i" "$student_name" "$repo_dir" "$home_dir" "$www_dir"
  done
}

ensure_default_index() {
  local index_path="$1"
  local student_name="$2"

  if [[ ! -f "$index_path" ]]; then
    cat <<EOF > "$index_path"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>${student_name} Lab</title>
</head>
<body>
  <h1>${student_name} Lab Ready</h1>
  <p>Place your static website in /var/www/html.</p>
  <p>Run your app on port 3000 inside the container for the dynamic link.</p>
</body>
</html>
EOF
  fi
}

ensure_student_runtime() {
  local student="$1"
  local password="$2"
  local home_dir="$3"
  local www_dir="$4"

  docker exec -e STUDENT_PASSWORD="$password" "$student" bash -lc '
    useradd -m -s /bin/bash -G sudo student || true
    printf "%s:%s\n" "student" "$STUDENT_PASSWORD" | chpasswd
    install -d -m 0750 /etc/sudoers.d
    echo "student ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/student
    chmod 0440 /etc/sudoers.d/student
    mkdir -p /home/student /var/www/html
    chmod 755 /home/student /var/www/html
    find /var/www/html -type d -exec chmod 755 {} \;
    find /var/www/html -type f -exec chmod 644 {} \;
    chown -R student:student /home/student /var/www/html
  ' || fail "Failed to initialize Linux user in $student."

  chown -R 1000:1000 "$home_dir" "$www_dir" || true
}

container_is_running() {
  local student="$1"
  [[ "$(docker inspect -f '{{.State.Running}}' "$student" 2>/dev/null || echo false)" == "true" ]]
}

capture_container_debug_info() {
  local student="$1"
  local log_file="/var/log/${student}-recovery.log"

  {
    echo "=== $(date -u '+%Y-%m-%d %H:%M:%S UTC') ==="
    docker inspect "$student" --format 'status={{.State.Status}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}} error={{.State.Error}} started={{.State.StartedAt}} finished={{.State.FinishedAt}}' 2>/dev/null || true
    docker logs "$student" 2>&1 || true
    echo
  } >> "$log_file"
}

remove_container_if_exists() {
  local student="$1"

  if docker container inspect "$student" >/dev/null 2>&1; then
    docker rm -f "$student" >/dev/null 2>&1 || true
  fi
}

create_student_container() {
  local student="$1"
  local ssh_port="$2"
  local http_port="$3"
  local app_port="$4"
  local home_dir="$5"
  local www_dir="$6"

  local docker_args=(
    -d
    --name "$student"
    --hostname "$student-lab"
    --network student-network
    --label cloud-lab.student=true
    --label cloud-lab.student-id="$student"
    --memory="$CONTAINER_MEMORY"
    --cpus="$CONTAINER_CPU"
    --restart unless-stopped
    --log-driver json-file
    --log-opt max-size=10m
    --log-opt max-file=3
    -p "$ssh_port:22"
    -v "$home_dir:/home/student"
    -v "$www_dir:/var/www/html"
  )

  if [[ "$ENABLE_STUDENT_WEB_ACCESS" == "true" ]]; then
    docker_args+=(-p "$http_port:8000")
  fi

  if [[ "$ENABLE_STUDENT_APP_PORT_ACCESS" == "true" ]]; then
    docker_args+=(-p "$app_port:3000")
  fi

  docker run "${docker_args[@]}" student-lab:latest >/dev/null || fail "Failed to create $student."
}

ensure_container_running() {
  local student="$1"
  local ssh_port="$2"
  local http_port="$3"
  local app_port="$4"
  local home_dir="$5"
  local www_dir="$6"

  if docker container inspect "$student" >/dev/null 2>&1; then
    docker start "$student" >/dev/null 2>&1 || true
    sleep 3
    if container_is_running "$student"; then
      return
    fi

    log "$student exists but did not stay running. Recreating it with the current image."
    capture_container_debug_info "$student"
    remove_container_if_exists "$student"
  fi

  create_student_container "$student" "$ssh_port" "$http_port" "$app_port" "$home_dir" "$www_dir"
  sleep 3
  if ! container_is_running "$student"; then
    capture_container_debug_info "$student"
    fail "$student exited immediately after recreation. Check /var/log/${student}-recovery.log or docker logs $student."
  fi
}

cleanup_legacy_container_diff() {
  local student="$1"
  local repo_dir="$LAB_ROOT/$student/state-repo"

  if [[ "$ENABLE_CONTAINER_STATE_RESTORE" == "true" ]]; then
    return
  fi

  rm -rf "$repo_dir/container-diff" >/dev/null 2>&1 || true
}

until docker info >/dev/null 2>&1; do
  log "Waiting for Docker..."
  sleep 5
done

mkdir -p "$LAB_ROOT" /opt/cloud-lab/dashboard/data /opt/cloud-lab/dashboard/assets
reset_runtime_after_host_change "$(detect_host_identity)"

load_github_token
restore_from_github

cd /opt/cloud-lab

retry 3 docker network inspect student-network >/dev/null 2>&1 || retry 3 docker network create student-network

cat <<'EOF' > Dockerfile
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -o Acquire::Retries=3 \
 && apt-get install -y --no-install-recommends \
    openssh-server \
    sudo \
    python3 \
    ca-certificates \
    curl \
    git \
    vim-tiny \
    nano \
 && mkdir -p /var/run/sshd /var/www/html \
 && rm -rf /var/lib/apt/lists/*

COPY start-services.sh /usr/local/bin/start-services.sh
RUN chmod +x /usr/local/bin/start-services.sh

EXPOSE 22 8000 3000

CMD ["/usr/local/bin/start-services.sh"]
EOF

cat <<'EOF' > start-services.sh
#!/bin/bash
set -euo pipefail

mkdir -p /var/run/sshd /var/www/html

if ! command -v sshd >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -o Acquire::Retries=3 >/dev/null 2>&1 || true
  apt-get install -y --no-install-recommends openssh-server >/dev/null 2>&1 || true
fi

mkdir -p /etc/ssh/sshd_config.d
if [ ! -f /etc/ssh/sshd_config ]; then
  cat <<'CONFIG' > /etc/ssh/sshd_config
Include /etc/ssh/sshd_config.d/*.conf
UsePAM yes
Subsystem sftp /usr/lib/openssh/sftp-server
CONFIG
fi

cat <<'CONFIG' > /etc/ssh/sshd_config.d/99-cloud-lab.conf
PasswordAuthentication yes
PermitRootLogin no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
PidFile /var/run/sshd.pid
CONFIG

if ! /usr/sbin/sshd -t >/dev/null 2>&1; then
  cat <<'CONFIG' > /etc/ssh/sshd_config
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
PermitRootLogin no
PasswordAuthentication yes
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
PidFile /var/run/sshd.pid
CONFIG
fi

ssh-keygen -A

if [ ! -f /var/www/html/index.html ]; then
  cat <<'HTML' > /var/www/html/index.html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Student Lab</title>
</head>
<body>
  <h1>Student Lab Ready</h1>
  <p>Place your static site in /var/www/html.</p>
  <p>Run any app on port 3000 for the dynamic app link.</p>
</body>
</html>
HTML
fi

if command -v python3 >/dev/null 2>&1; then
  pkill -f "python3 -m http.server 8000" >/dev/null 2>&1 || true
  nohup python3 -m http.server 8000 --directory /var/www/html >/var/log/student-static.log 2>&1 &
fi
exec /usr/sbin/sshd -D -e
EOF

build_student_image_if_needed

for i in $(seq 1 "$STUDENT_COUNT"); do
  STUDENT="student$i"
  SSH_PORT=$((2200 + i))
  HTTP_PORT=$((STUDENT_WEB_PORT_START + i - 1))
  APP_PORT=$((STUDENT_APP_PORT_START + i - 1))
  PASSWORD=$(echo "$CREDENTIALS_JSON" | jq -r ".[$((i-1))].password")
  HOME_DIR="$LAB_ROOT/$STUDENT/home"
  WWW_DIR="$LAB_ROOT/$STUDENT/www"

  if [[ -z "$PASSWORD" || "$PASSWORD" == "null" || ${#PASSWORD} -lt 8 ]]; then
    PASSWORD="Student@123"
  fi

  mkdir -p "$HOME_DIR" "$WWW_DIR"
  chmod 755 "$LAB_ROOT/$STUDENT" "$HOME_DIR" "$WWW_DIR"
  ensure_default_index "$WWW_DIR/index.html" "$STUDENT"

  log "Ensuring container runtime for $STUDENT on SSH $SSH_PORT, web $HTTP_PORT, app $APP_PORT."
  ensure_container_running "$STUDENT" "$SSH_PORT" "$HTTP_PORT" "$APP_PORT" "$HOME_DIR" "$WWW_DIR"
  cleanup_legacy_container_diff "$STUDENT"

  if [[ "$ENABLE_GITHUB_SYNC" == "true" && "$GITHUB_SYNC_ACTIVE" == "true" ]]; then
    if ! restore_container_diff "$STUDENT" "$LAB_ROOT/$STUDENT/state-repo"; then
      log "Falling back to a clean container for $STUDENT after restore failure."
      remove_container_if_exists "$STUDENT"
      create_student_container "$STUDENT" "$SSH_PORT" "$HTTP_PORT" "$APP_PORT" "$HOME_DIR" "$WWW_DIR"
      sleep 3
      container_is_running "$STUDENT" || fail "$STUDENT could not be restarted after restore fallback."
    fi
  fi

  container_is_running "$STUDENT" || fail "$STUDENT is not running after restore."

  ensure_student_runtime "$STUDENT" "$PASSWORD" "$HOME_DIR" "$WWW_DIR"

  cat <<EOF > "$LAB_ROOT/$STUDENT/.lab-metadata"
student_id=$STUDENT
ssh_port=$SSH_PORT
http_port=$HTTP_PORT
app_port=$APP_PORT
EOF
done

/opt/cloud-lab/collect-usage.sh || true
/opt/cloud-lab/generate-report.sh || true

if [[ "$ENABLE_ADMIN_DASHBOARD" == "true" ]]; then
  /opt/cloud-lab/render-dashboard.sh || true
fi

/opt/cloud-lab/sync-data.sh || true
/opt/cloud-lab/backup-data.sh || true

alert "Cloud Lab setup completed" "Your lab server finished setup and student environments are ready."
log "Cloud Lab setup completed."
