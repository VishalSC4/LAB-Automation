#!/bin/bash

set -euo pipefail

source /root/lab.env

AWS_REGION=${aws_region:-ap-south-1}
export AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

STUDENT_COUNT=${student_count:-5}
ENABLE_GITHUB_SYNC=${enable_github_sync:-false}
ENABLE_CONTAINER_STATE_RESTORE=${enable_container_state_restore:-false}
ENABLE_REPO_BOOTSTRAP=${enable_repo_bootstrap:-false}
ENABLE_ADMIN_DASHBOARD=${enable_admin_dashboard:-true}
GITHUB_ORG=${github_org:-}
GITHUB_REPO_PREFIX=${github_repo_prefix:-student-lab}
GITHUB_REPOSITORY_URL=${github_repository_url:-}
GITHUB_BRANCH=${github_branch:-main}
GITHUB_STUDENT_BRANCH_PREFIX=${github_student_branch_prefix:-student-}
GITHUB_TOKEN_SSM_PARAMETER=${github_token_ssm_parameter:-}
GIT_AUTHOR_NAME=${github_commit_author_name:-Cloud Lab Bot}
GIT_AUTHOR_EMAIL=${github_commit_author_email:-cloud-lab-bot@example.com}
LAB_ROOT=${lab_data_mount_point:-/lab-data}
GIT_TOKEN=""
GITHUB_SYNC_ACTIVE=false

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

resolve_repo_and_branch() {
  local student_index="$1"

  if [[ -n "$GITHUB_REPOSITORY_URL" ]]; then
    RESOLVED_REPO_URL="$GITHUB_REPOSITORY_URL"
    RESOLVED_BRANCH="${GITHUB_STUDENT_BRANCH_PREFIX}${student_index}"
    return
  fi

  if [[ -z "$GITHUB_ORG" ]]; then
    return 1
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
  if [[ "$ENABLE_GITHUB_SYNC" != "true" || -z "$GITHUB_TOKEN_SSM_PARAMETER" ]]; then
    return
  fi

  GIT_TOKEN=$(aws ssm get-parameter \
    --region "$AWS_REGION" \
    --name "$GITHUB_TOKEN_SSM_PARAMETER" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text 2>/dev/null || true)

  if [[ -z "$GIT_TOKEN" || "$GIT_TOKEN" == "None" ]]; then
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

  if [[ "$ENABLE_REPO_BOOTSTRAP" != "true" || "$GITHUB_SYNC_ACTIVE" != "true" ]]; then
    return
  fi

  if [[ -n "$GITHUB_REPOSITORY_URL" ]]; then
    if ! git ls-remote --exit-code --heads "$repo_url" "$branch_name" >/dev/null 2>&1; then
      local temp_dir
      temp_dir=$(mktemp -d)
      git -C "$temp_dir" init -b "$branch_name" >/dev/null 2>&1
      echo "# Student ${student_index} Lab State" > "$temp_dir/README.md"
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

prepare_repo() {
  local student_index="$1"
  local repo_dir="$2"

  resolve_repo_and_branch "$student_index" || return 0
  local repo_url="$RESOLVED_REPO_URL"
  local target_branch="$RESOLVED_BRANCH"

  bootstrap_repo_if_needed "$student_index" "$repo_url" "$target_branch"

  if [[ ! -d "$repo_dir/.git" ]]; then
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
  fi
}

ensure_repo_scaffold() {
  local student_name="$1"
  local repo_dir="$2"
  local home_dir="$3"
  local www_dir="$4"

  mkdir -p "$repo_dir/home" "$repo_dir/www"

  if [[ ! -f "$repo_dir/README.md" ]]; then
    cat <<EOF > "$repo_dir/README.md"
# ${student_name^} Lab State

This branch is managed by Cloud Lab automation.
EOF
  fi

  cat <<EOF > "$repo_dir/RESTORE_INFO.txt"
Student: $student_name
Last sync (UTC): $(date -u '+%Y-%m-%d %H:%M:%S UTC')
home/ -> /home/student
www/ -> /var/www/html
EOF

  [[ -f "$LAB_ROOT/$student_name/.lab-metadata" ]] && cp "$LAB_ROOT/$student_name/.lab-metadata" "$repo_dir/lab-metadata.env"

  if [[ -z "$(find "$home_dir" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
    touch "$home_dir/.gitkeep"
  fi

  if [[ -z "$(find "$www_dir" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
    touch "$www_dir/.gitkeep"
  fi
}

stage_student_state() {
  local student_name="$1"
  local home_dir="$2"
  local www_dir="$3"
  local repo_dir="$4"

  ensure_repo_scaffold "$student_name" "$repo_dir" "$home_dir" "$www_dir"

  rsync -a --delete --exclude '.git/' --exclude '.cache/' "$home_dir"/ "$repo_dir/home"/
  rsync -a --delete "$www_dir"/ "$repo_dir/www"/
}

stage_container_diff() {
  if [[ "$ENABLE_CONTAINER_STATE_RESTORE" != "true" ]]; then
    rm -rf "$2/container-diff" >/dev/null 2>&1 || true
    return
  fi

  local container_name="$1"
  local repo_dir="$2"
  local diff_root="$repo_dir/container-diff"
  local files_dir="$diff_root/files"
  local deletions_file="$diff_root/deletions.txt"

  rm -rf "$files_dir"
  mkdir -p "$files_dir"
  : > "$deletions_file"

  if ! docker container inspect "$container_name" >/dev/null 2>&1; then
    return
  fi

  while IFS= read -r diff_line; do
    [[ -z "$diff_line" ]] && continue

    local action="${diff_line%% *}"
    local path="${diff_line#??}"

    should_skip_container_path "$path" && continue

    case "$action" in
      A|C)
        local target_parent="$files_dir$(dirname "$path")"
        mkdir -p "$target_parent"
        docker cp "$container_name:$path" "$target_parent/" >/dev/null 2>&1 || true
        ;;
      D)
        printf '%s\n' "$path" >> "$deletions_file"
        ;;
    esac
  done < <(docker diff "$container_name")

  [[ -z "$(find "$files_dir" -mindepth 1 -print -quit 2>/dev/null)" ]] && rm -rf "$files_dir"
  [[ ! -s "$deletions_file" ]] && rm -f "$deletions_file"
}

sync_github_workspaces() {
  if [[ "$ENABLE_GITHUB_SYNC" != "true" || "$GITHUB_SYNC_ACTIVE" != "true" ]]; then
    log "GitHub sync is disabled or not configured."
    return
  fi

  export GIT_ASKPASS=/root/.lab-git-askpass
  export GIT_TERMINAL_PROMPT=0

  for i in $(seq 1 "$STUDENT_COUNT"); do
    STUDENT="student$i"
    HOME_DIR="$LAB_ROOT/$STUDENT/home"
    WWW_DIR="$LAB_ROOT/$STUDENT/www"
    REPO_DIR="$LAB_ROOT/$STUDENT/state-repo"

    mkdir -p "$HOME_DIR" "$WWW_DIR" "$REPO_DIR"
    prepare_repo "$i" "$REPO_DIR"
    stage_student_state "$STUDENT" "$HOME_DIR" "$WWW_DIR" "$REPO_DIR"
    stage_container_diff "$STUDENT" "$REPO_DIR"

    git -C "$REPO_DIR" add -A
    if ! git -C "$REPO_DIR" diff --cached --quiet; then
      git -C "$REPO_DIR" commit -m "Auto-sync $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >/dev/null 2>&1 || true
    fi

    resolve_repo_and_branch "$i" || continue
    git -C "$REPO_DIR" push origin "$RESOLVED_BRANCH" >/dev/null 2>&1 || log "Push failed for $STUDENT."
  done
}

mkdir -p "$LAB_ROOT"
load_github_token
sync_github_workspaces
/opt/cloud-lab/generate-report.sh >/dev/null 2>&1 || true
if [[ "$ENABLE_ADMIN_DASHBOARD" == "true" ]]; then
  /opt/cloud-lab/render-dashboard.sh >/dev/null 2>&1 || true
fi
log "GitHub state sync complete."
