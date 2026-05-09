#!/bin/bash

# CCPM Sync Script — Push epic + tasks to GitLab and update checkboxes for closed tasks
# Usage: bash references/scripts/sync.sh [epic-name]

set -e

CCPM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(cd "$CCPM_DIR/../../../.." && pwd)"

cd "$PROJECT_ROOT"

# Parse arguments
EPIC_NAME="${1:-}"

# Helper functions
log_info() {
  echo "ℹ️  $1"
}

log_success() {
  echo "✅ $1"
}

log_error() {
  echo "❌ $1"
}

log_warning() {
  echo "⚠️  $1"
}

# Repo safety check
check_repo() {
  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null || echo "")

  if [[ -z "$remote_url" ]]; then
    log_error "No git remote found. Set up a GitLab remote first."
    exit 1
  fi

  # Extract host and repo
  GITLAB_HOST=$(echo "$remote_url" | sed -E 's|https?://([^/]+)/.*|\1|' | sed -E 's|git@([^:]+):.*|\1|')
  REPO=$(echo "$remote_url" | sed -E 's|https?://[^/]+/||' | sed -E 's|git@[^:]+:||' | sed 's|\.git$||')

  if [[ "$REPO" == "automazeio/ccpm" ]] || [[ "$REPO" == "anthropics/ccpm" ]]; then
    log_error "Cannot sync to the CCPM template repository."
    log_error "Update remote: git remote set-url origin https://$GITLAB_HOST/YOUR_GROUP/YOUR_REPO.git"
    exit 1
  fi
}

# Sync acceptance criteria checkboxes from local task file to GitLab issue description
sync_task_issue_description() {
  local task_file="$1"
  local epic_name="$2"

  if [[ ! -f "$task_file" ]]; then
    return
  fi

  # Extract task number from filename
  local task_num
  task_num=$(basename "$task_file" .md)

  # Check if task has a gitlab URL
  local gitlab_url
  gitlab_url=$(grep '^gitlab:' "$task_file" 2>/dev/null | sed 's|^gitlab: ||')

  if [[ -z "$gitlab_url" ]]; then
    return
  fi

  # Extract task number from gitlab URL
  local issue_num
  issue_num=$(echo "$gitlab_url" | grep -oE '[0-9]+$' || echo "")

  if [[ -z "$issue_num" ]]; then
    return
  fi

  # Strip YAML frontmatter to get just the body
  local body
  body=$(awk '/^---/ { if (++fence == 2) { skip=0; next } else { skip=1; next } } skip { next } { print }' "$task_file")

  if [[ -z "$body" ]]; then
    return
  fi

  # Update GitLab issue description with the body
  glab issue update "$issue_num" --description "$body" 2>/dev/null
  log_success "Synced task #$task_num acceptance criteria to GitLab issue #$issue_num"
}

# Update checkboxes for closed tasks in an epic
update_epic_checkboxes() {
  local epic_dir="$1"
  local epic_name="$2"

  if [[ ! -f "$epic_dir/epic.md" ]]; then
    log_warning "Epic file not found: $epic_dir/epic.md"
    return
  fi

  # Get GitLab issue number from epic.md
  local gitlab_url
  gitlab_url=$(grep '^gitlab:' "$epic_dir/epic.md" 2>/dev/null | head -1 | sed 's|^gitlab: ||')

  if [[ -z "$gitlab_url" ]]; then
    log_info "Epic $epic_name not synced to GitLab yet (no gitlab: field)"
    return
  fi

  local epic_num
  epic_num=$(echo "$gitlab_url" | grep -oE '[0-9]+$' || echo "")

  if [[ -z "$epic_num" ]]; then
    log_warning "Could not extract issue number from: $gitlab_url"
    return
  fi

  log_info "Updating checkboxes for epic #$epic_num ($epic_name)..."

  # Count total and closed tasks
  local total_tasks=0
  local closed_tasks=0
  local task_files=()

  for task_file in "$epic_dir"/[0-9]*.md; do
    [[ -f "$task_file" ]] || continue
    total_tasks=$((total_tasks + 1))
    task_files+=("$task_file")

    # Check if task is closed
    if grep -q '^status: closed' "$task_file"; then
      closed_tasks=$((closed_tasks + 1))
    fi
  done

  if [[ $total_tasks -eq 0 ]]; then
    log_warning "No task files found in $epic_dir"
    return
  fi

  # Get current epic description from GitLab
  local epic_body
  epic_body=$(glab issue view "$epic_num" --output json 2>/dev/null | jq -r '.description' || echo "")

  if [[ -z "$epic_body" ]]; then
    log_warning "Could not fetch epic #$epic_num from GitLab"
    return
  fi

  # Update checkboxes in the description
  local updated_body="$epic_body"

  for task_file in "${task_files[@]}"; do
    [[ -f "$task_file" ]] || continue

    local task_num
    task_num=$(basename "$task_file" .md)

    # Get task name/title
    local task_name
    task_name=$(grep '^name:' "$task_file" | cut -d':' -f2- | xargs)

    # Check if task is closed
    if grep -q '^status: closed' "$task_file"; then
      # Mark as done
      updated_body=$(echo "$updated_body" | sed "s/- \[ \] #$task_num:/- [x] #$task_num:/g")
      log_success "Marking task #$task_num as done: $task_name"
    fi

    # Also sync the task issue description with acceptance criteria
    sync_task_issue_description "$task_file" "$epic_name"
  done

  # Update epic issue on GitLab
  if [[ "$updated_body" != "$epic_body" ]]; then
    glab issue update "$epic_num" --description "$updated_body" 2>/dev/null
    log_success "Epic issue updated on GitLab"
  fi

  # Update progress in epic.md
  if [[ $total_tasks -gt 0 ]]; then
    local progress=$((closed_tasks * 100 / total_tasks))
    sed -i.bak "/^progress:/c\\progress: ${progress}%" "$epic_dir/epic.md"
    rm -f "$epic_dir/epic.md.bak"
  fi

  log_success "Progress: $closed_tasks/$total_tasks tasks closed ($(( closed_tasks * 100 / total_tasks ))%)"
}

# Main
check_repo

echo "🔄 Syncing to GitLab..."
echo ""

if [[ -n "$EPIC_NAME" ]]; then
  # Sync specific epic
  epic_dir=".claude/epics/$EPIC_NAME"

  if [[ ! -d "$epic_dir" ]]; then
    log_error "Epic directory not found: $epic_dir"
    exit 1
  fi

  update_epic_checkboxes "$epic_dir" "$EPIC_NAME"
else
  # Sync all epics
  for epic_dir in .claude/epics/*/; do
    [[ -d "$epic_dir" ]] || continue

    epic_name=$(basename "$epic_dir")

    # Skip archived epics
    [[ "$epic_name" == "archived" ]] && continue

    echo "📋 Epic: $epic_name"
    update_epic_checkboxes "$epic_dir" "$epic_name"
    echo ""
  done
fi

log_success "All epics synced!"
