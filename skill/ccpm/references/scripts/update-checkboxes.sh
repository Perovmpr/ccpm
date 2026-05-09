#!/bin/bash
# Update checkboxes for all closed tasks in all epics
# Marks task checkboxes as [x] in epic issue body when local task status is closed
# Syncs acceptance criteria from task files to GitLab issue descriptions
# Updates both GitLab and recalculates epic progress

set -e

EPICS_DIR=".claude/epics"

if [ ! -d "$EPICS_DIR" ]; then
  echo "❌ No .claude/epics directory found. Run this in the project root."
  exit 1
fi

# Repository safety check
remote_url=$(git remote get-url origin 2>/dev/null || echo "")
GITLAB_HOST=$(echo "$remote_url" | sed -E 's|https?://([^/]+)/.*|\1|' | sed -E 's|git@([^:]+):.*|\1|')
REPO=$(echo "$remote_url" | sed -E 's|https?://[^/]+/||' | sed -E 's|git@[^:]+:||' | sed 's|\.git$||')

if [[ "$REPO" == "automazeio/ccpm" ]]; then
  echo "❌ Cannot update checkboxes in the CCPM template repository."
  exit 1
fi

# Function to sync task acceptance criteria to GitLab issue description
sync_task_description() {
  local task_file="$1"

  if [[ ! -f "$task_file" ]]; then
    return
  fi

  # Extract gitlab URL from frontmatter
  local gitlab_url
  gitlab_url=$(grep '^gitlab:' "$task_file" 2>/dev/null | sed 's|^gitlab: ||')

  if [[ -z "$gitlab_url" ]]; then
    return
  fi

  # Extract issue number from URL
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

  # Update GitLab issue description
  glab issue update "$issue_num" --description "$body" 2>/dev/null
}

echo "🔄 Updating checkboxes for all closed tasks..."
echo ""

# Iterate through all epics
for epic_dir in "$EPICS_DIR"/*/; do
  epic_name=$(basename "$epic_dir")

  # Skip archived epics
  if [[ "$epic_name" == "archived" ]]; then
    continue
  fi

  epic_file="$epic_dir/epic.md"

  if [ ! -f "$epic_file" ]; then
    continue
  fi

  # Get epic issue number from frontmatter
  epic_num=$(grep '^gitlab:' "$epic_file" 2>/dev/null | grep -oE '[0-9]+$' || echo "")

  if [ -z "$epic_num" ]; then
    echo "⚠️  Epic '$epic_name' not synced to GitLab yet. Skipping."
    continue
  fi

  echo "📋 Epic: $epic_name (issue #$epic_num)"

  # Get current epic body from GitLab
  epic_body=$(glab issue view "$epic_num" --output json 2>/dev/null | jq -r '.description' || echo "")

  if [ -z "$epic_body" ]; then
    echo "  ❌ Could not fetch epic issue from GitLab"
    continue
  fi

  echo "$epic_body" > /tmp/epic-body.md
  updated=false

  # Find all task files for this epic
  for task_file in "$epic_dir"/[0-9]*.md; do
    [ -f "$task_file" ] || continue

    task_num=$(basename "$task_file" .md)
    task_name=$(grep '^name:' "$task_file" 2>/dev/null | cut -d':' -f2- | xargs)
    task_status=$(grep '^status:' "$task_file" 2>/dev/null | cut -d':' -f2- | xargs)

    if [ "$task_status" = "closed" ]; then
      # Check if this task's checkbox is still unchecked
      if grep -q "- \[ \] #$task_num:" /tmp/epic-body.md; then
        echo "  ✅ Marking task #$task_num as done: $task_name"
        sed -i.bak "s/- \[ \] #$task_num:/- [x] #$task_num:/g" /tmp/epic-body.md
        rm /tmp/epic-body.md.bak
        updated=true
      fi
    fi

    # Sync task acceptance criteria to GitLab issue description
    sync_task_description "$task_file"
  done

  # Update epic issue on GitLab if changes were made
  if [ "$updated" = true ]; then
    glab issue update "$epic_num" --description "$(cat /tmp/epic-body.md)" 2>/dev/null
    echo "  ✨ Epic issue updated on GitLab"
  fi

  # Recalculate epic progress
  total=$(ls "$epic_dir"/[0-9]*.md 2>/dev/null | wc -l)
  closed=$(grep -l '^status: closed' "$epic_dir"/[0-9]*.md 2>/dev/null | wc -l)

  if [ "$total" -gt 0 ]; then
    progress=$((closed * 100 / total))

    # Update epic.md frontmatter
    sed -i.bak "/^progress:/c\\progress: ${progress}%" "$epic_file"
    rm "$epic_file.bak"

    echo "  📊 Progress: $closed/$total tasks closed ($progress%)"
  fi

  echo ""
done

echo "✅ All checkboxes updated!"
echo ""
echo "Summary:"
echo "  - Closed tasks are now marked [x] in epic issues"
echo "  - Epic progress has been recalculated"
echo "  - Changes synced to GitLab"
