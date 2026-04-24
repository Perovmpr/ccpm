#!/bin/bash

echo "Initializing..."
echo ""
echo ""

echo " ██████╗ ██████╗██████╗ ███╗   ███╗"
echo "██╔════╝██╔════╝██╔══██╗████╗ ████║"
echo "██║     ██║     ██████╔╝██╔████╔██║"
echo "╚██████╗╚██████╗██║     ██║ ╚═╝ ██║"
echo " ╚═════╝ ╚═════╝╚═╝     ╚═╝     ╚═╝"

echo "┌─────────────────────────────────┐"
echo "│ Claude Code Project Management  │"
echo "│ by https://x.com/aroussi        │"
echo "└─────────────────────────────────┘"
echo "https://gitlab.com/automazeio/ccpm"
echo ""
echo ""

echo "🚀 Initializing Claude Code PM System"
echo "======================================"
echo ""

# Check for required tools
echo "🔍 Checking dependencies..."

# Check glab CLI
if command -v glab &> /dev/null; then
  echo "  ✅ GitLab CLI (glab) installed"
else
  echo "  ❌ GitLab CLI (glab) not found"
  echo ""
  echo "  Installing glab..."
  if command -v brew &> /dev/null; then
    brew install glab
  elif command -v apt-get &> /dev/null; then
    sudo apt-get update && sudo apt-get install glab
  else
    echo "  Please install GitLab CLI manually: https://gitlab.com/gitlab-org/cli"
    exit 1
  fi
fi

# Check glab auth status
echo ""
echo "🔐 Checking GitLab authentication..."
if glab auth status &> /dev/null; then
  echo "  ✅ GitLab authenticated"
else
  echo "  ⚠️ GitLab not authenticated"
  echo "  Running: glab auth login"
  glab auth login
fi

# Create directory structure
echo ""
echo "📁 Creating directory structure..."
mkdir -p .claude/prds
mkdir -p .claude/epics
mkdir -p .claude/rules
mkdir -p .claude/agents
mkdir -p .claude/scripts/pm
echo "  ✅ Directories created"

# Copy scripts if in main repo
if [ -d "scripts/pm" ] && [ ! "$(pwd)" = *"/.claude"* ]; then
  echo ""
  echo "📝 Copying PM scripts..."
  cp -r scripts/pm/* .claude/scripts/pm/
  chmod +x .claude/scripts/pm/*.sh
  echo "  ✅ Scripts copied and made executable"
fi

# Check for git
echo ""
echo "🔗 Checking Git configuration..."
if git rev-parse --git-dir > /dev/null 2>&1; then
  echo "  ✅ Git repository detected"

  # Check remote
  if git remote -v | grep -q origin; then
    remote_url=$(git remote get-url origin)
    echo "  ✅ Remote configured: $remote_url"
    
    # Check if remote is the CCPM template repository
    GITLAB_HOST=$(echo "$remote_url" | sed -E 's|https?://([^/]+)/.*|\1|' | sed -E 's|git@([^:]+):.*|\1|')
    REPO=$(echo "$remote_url" | sed -E 's|https?://[^/]+/||' | sed -E 's|git@[^:]+:||' | sed 's|\.git$||')

    if [[ "$REPO" == "automazeio/ccpm" ]]; then
      echo ""
      echo "  ⚠️ WARNING: Your remote origin points to the CCPM template repository!"
      echo "  This means any issues you create will go to the template repo, not your project."
      echo ""
      echo "  To fix this:"
      echo "  1. Fork the repository or create your own on GitLab ($GITLAB_HOST)"
      echo "  2. Update your remote:"
      echo "     git remote set-url origin https://$GITLAB_HOST/YOUR_GROUP/YOUR_REPO.git"
      echo ""
    else
      # Create GitLab labels if this is a GitLab repository
      if glab repo view &> /dev/null; then
        echo ""
        echo "🏷️ Creating GitLab labels..."

        # Create base labels with improved error handling
        epic_created=false
        task_created=false

        if glab label create "epic" --color "#0E8A16" --description "Epic issue containing multiple related tasks" 2>/dev/null; then
          epic_created=true
        elif glab label list 2>/dev/null | grep -q "epic"; then
          epic_created=true  # Label already exists
        fi

        if glab label create "task" --color "#1D76DB" --description "Individual task within an epic" 2>/dev/null; then
          task_created=true
        elif glab label list 2>/dev/null | grep -q "task"; then
          task_created=true  # Label already exists
        fi

        # Report results
        if $epic_created && $task_created; then
          echo "  ✅ GitLab labels created (epic, task)"
        elif $epic_created || $task_created; then
          echo "  ⚠️ Some GitLab labels created (epic: $epic_created, task: $task_created)"
        else
          echo "  ❌ Could not create GitLab labels (check repository permissions)"
        fi
      else
        echo "  ℹ️ Not a GitLab repository - skipping label creation"
      fi
    fi
  else
    echo "  ⚠️ No remote configured"
    echo "  Add with: git remote add origin <url>"
  fi
else
  echo "  ⚠️ Not a git repository"
  echo "  Initialize with: git init"
fi

# Create CLAUDE.md if it doesn't exist
if [ ! -f "CLAUDE.md" ]; then
  echo ""
  echo "📄 Creating CLAUDE.md..."
  cat > CLAUDE.md << 'EOF'
# CLAUDE.md

> Think carefully and implement the most concise solution that changes as little code as possible.

## Project-Specific Instructions

Add your project-specific instructions here.

## Testing

Always run tests before committing:
- `npm test` or equivalent for your stack

## Code Style

Follow existing patterns in the codebase.
EOF
  echo "  ✅ CLAUDE.md created"
fi

# Summary
echo ""
echo "✅ Initialization Complete!"
echo "=========================="
echo ""
echo "📊 System Status:"
glab version | head -1
echo "  Auth: $(glab auth status 2>&1 | head -1 || echo 'Not authenticated')"
echo ""
echo "🎯 Next Steps:"
echo "  1. Create your first PRD: /pm:prd-new <feature-name>"
echo "  2. View help: /pm:help"
echo "  3. Check status: /pm:status"
echo ""
echo "📚 Documentation: README.md"

exit 0
