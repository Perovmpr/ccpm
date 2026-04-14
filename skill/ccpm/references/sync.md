# Sync — Push to GitLab & Track Progress

This phase covers pushing local epics/tasks to GitLab as issues, syncing progress as comments, and closing issues when work is done.

---

## Repository Safety Check

**Always run this before any GitLab write operation:**

```bash
remote_url=$(git remote get-url origin 2>/dev/null || echo "")
if [[ "$remote_url" == *"automazeio/ccpm"* ]]; then
  echo "❌ Cannot sync to the CCPM template repository."
  echo "Update remote: git remote set-url origin https://gitlab.com/YOUR/REPO.git"
  exit 1
fi
REPO=$(echo "$remote_url" | sed 's|.*gitlab.com[:/]||' | sed 's|\.git$||')
```

---

## Epic Sync — Push Epic + Tasks to GitLab

**Trigger**: User wants to push a local epic and its tasks to GitLab as issues.

### Preflight
- Verify `.qwen/epics/<name>/epic.md` exists.
- Verify numbered task files exist — if none: "❌ No tasks to sync. Decompose the epic first."

### Process

**Step 1 — Create epic issue:**

Strip frontmatter from epic.md, then:
```bash
sed '1,/^---$/d; 1,/^---$/d' .qwen/epics/<name>/epic.md > /tmp/epic-body.md
epic_number=$(glab issue create \
  --repo "$REPO" \
  --title "Epic: <name>" \
  --description-file /tmp/epic-body.md \
  --label "epic,epic:<name>,feature" \
  | grep -oE '#[0-9]+' | tr -d '#')
```

**Step 2 — Create task issues:**

GitLab does not have sub-issues like GitHub. Instead, tasks are linked to the epic via:
- Shared label: `epic:<name>`
- Epic issue body contains a task list: `- [ ] #<task_N> <title>`

For <5 tasks: create sequentially.
For ≥5 tasks: use parallel Task agents (3-4 tasks per batch).

Per task:
```bash
sed '1,/^---$/d; 1,/^---$/d' <task_file> > /tmp/task-body.md
task_number=$(glab issue create \
  --repo "$REPO" \
  --title "<task_name>" \
  --description-file /tmp/task-body.md \
  --label "task,epic:<name>" \
  | grep -oE '#[0-9]+' | tr -d '#')
```

After the epic issue is created, update its body to include a task list linking to all tasks:
```markdown
## Tasks
- [ ] #<task_1_N> <task_1_title>
- [ ] #<task_2_N> <task_2_title>
...
```

Post this update via:
```bash
glab issue update "$epic_number" --description-file /tmp/epic-with-tasks.md
```

**Step 3 — Rename task files and update references:**

After all issues are created, rename `001.md` → `<issue_number>.md` and update all `depends_on`/`conflicts_with` arrays to use real issue numbers (not sequential numbers).

```bash
# Build old→new mapping, then for each task file:
sed -i.bak "s/\b001\b/<new_num_1>/g" <file>  # repeat for each mapping
mv 001.md <new_num>.md
```

**Step 4 — Update frontmatter:**
```bash
current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Update gitlab: and updated: fields in epic.md and each task file
gitlab_url="https://gitlab.com/$REPO/-/issues/<number>"
sed -i.bak "/^gitlab:/c\\gitlab: $gitlab_url" <file>
sed -i.bak "/^updated:/c\\updated: $current_date" <file>
rm <file>.bak
```

**Step 5 — Create worktree for the epic:**
```bash
git checkout main && git pull origin main
git worktree add ../epic-<name> -b epic/<name>
```

**Step 6 — Create gitlab-mapping.md:**
```markdown
# GitLab Issue Mapping
Epic: #<N> - https://gitlab.com/<repo>/-/issues/<N>
Tasks:
- #<N>: <title> - https://gitlab.com/<repo>/-/issues/<N>
Synced: <datetime>
```

**Output:**
```
✅ Synced epic <name> to GitLab
  Epic: #<N>
  Tasks: N issues
  Worktree: ../epic-<name>
  Next: "start working on issue <N>" or "start the <name> epic"
```

---

## Issue Sync — Post Progress to GitLab

**Trigger**: User wants to sync local development progress to a GitLab issue as a comment.

### Preflight
- Verify issue exists: `glab issue view <N>`
- Check `.qwen/epics/*/updates/<N>/` exists with a `progress.md` file.
- Check `last_sync` in progress.md — if synced <5 minutes ago, confirm before proceeding.

### Process

Gather updates from `.qwen/epics/<epic>/updates/<N>/` (progress.md, notes.md, commits.md).

Format and post a comment (note):
```bash
glab issue note create <N> --file /tmp/update-comment.md
```

Comment format:
```markdown
## 🔄 Progress Update - <date>

### ✅ Completed Work
### 🔄 In Progress
### 📝 Technical Notes
### 📊 Acceptance Criteria Status
### 🚀 Next Steps
### ⚠️ Blockers

---
*Progress: N% | Synced at <timestamp>*
```

After posting: update `last_sync` in progress.md frontmatter, update `updated` in the task file.

Add sync marker to local files to prevent duplicate comments:
```markdown
<!-- SYNCED: <datetime> -->
```

---

## Closing an Issue

**Trigger**: User marks a task complete.

### Process

1. Find the local task file (`.qwen/epics/*/<N>.md`).
2. Update frontmatter: `status: closed`, `updated: <now>`.
3. Post completion comment and close:
```bash
glab issue note create <N> --message "✅ Task completed — all acceptance criteria met."
glab issue close <N>
```
4. Check off the task in the epic issue body:
```bash
# Fetch current epic body, update checkbox, push back
glab issue view <epic_N> --json description -q .description > /tmp/epic-body.md
sed -i "s/- \[ \] #<N>/- [x] #<N>/" /tmp/epic-body.md
glab issue update <epic_N> --description-file /tmp/epic-body.md
```
5. Recalculate and update epic progress: `progress = closed_tasks / total_tasks * 100`

---

## Merging an Epic

**Trigger**: User wants to merge a completed epic back to main.

### Preflight
- Verify worktree `../epic-<name>` exists.
- Check for uncommitted changes in the worktree — block if dirty.
- Warn if any task issues are still open.

### Process

```bash
# From worktree: run project tests if detectable
cd ../epic-<name>
# detect and run: npm test / pytest / cargo test / go test / etc.

# From main repo:
git checkout main && git pull origin main
git merge epic/<name> --no-ff -m "Merge epic: <name>"
git push origin main

# Cleanup
git worktree remove ../epic-<name>
git branch -d epic/<name>
git push origin --delete epic/<name>

# Archive
mkdir -p .qwen/epics/archived/
mv .qwen/epics/<name> .qwen/epics/archived/

# Close GitLab issues
epic_issue=$(grep 'gitlab:' .qwen/epics/archived/<name>/epic.md | grep -oE '[0-9]+$')
glab issue close "$epic_issue" --message "Epic completed and merged to main"
```

Update epic.md frontmatter: `status: completed`.

---

## Reporting a Bug Against a Completed Issue

**Trigger**: User finds a bug while testing a completed or in-progress issue — e.g. "found a bug in issue 42", "email validation is broken, came up while testing issue 42".

The workflow should stay автоматизированной: create a linked bug task without losing context from the original issue.

### Process

**Step 1 — Read the original issue for context:**
```bash
glab issue view <original_N> --json title,description,labels
```
Also read the local task file if it exists: `.qwen/epics/*/<original_N>.md`

**Step 2 — Create a local bug task file:**

```markdown
---
name: Bug: <short description>
status: open
created: <run: date -u +"%Y-%m-%dT%H:%M:%SZ">
updated: <same>
gitlab: (will be set on sync)
depends_on: []
parallel: false
conflicts_with: []
bug_for: <original_N>
---

# Bug: <short description>

## Context
Found while working on / testing issue #<original_N>: <original title>

## Description
<what's broken>

## Steps to Reproduce
<steps>

## Expected vs Actual
- Expected:
- Actual:

## Acceptance Criteria
- [ ] Bug is fixed
- [ ] Original issue #<original_N> behaviour is unaffected

## Effort Estimate
- Size: XS/S
```

Save to `.qwen/epics/<same_epic_as_original>/bug-<original_N>-<slug>.md`

**Step 3 — Create a linked GitLab issue:**
```bash
glab issue create \
  --repo "$REPO" \
  --title "Bug: <short description>" \
  --description-file /tmp/bug-body.md \
  --label "bug,epic:<epic_name>" \
  | grep -oE '#[0-9]+' | tr -d '#'
```

The issue body should open with `Related to #<original_N>` so GitLab links them via auto-reference.

**Step 4 — Update the local file** with the GitLab issue number and rename to `<new_N>.md`.

**Output:**
```
✅ Bug issue created: #<new_N> — "Bug: <short description>"
  Linked to: #<original_N>
  Epic: <epic_name>

Start fixing it: "start working on issue <new_N>"
```
