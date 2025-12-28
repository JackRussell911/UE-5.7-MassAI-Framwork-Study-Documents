#!/bin/bash
# Mass AI Docs - GitHub Auto Sync Script (Bash version for Claude Code hooks)
# Usage: ./sync-to-github.sh "commit message"

DOCS_PATH="C:/Users/RussellMainV3/Perforce/RussellV3_ProjectRYU/Docs/MassAI"
MESSAGE="${1:-Update Mass AI documentation}"

cd "$DOCS_PATH"

# Check for changes
if [ -z "$(git status --porcelain)" ]; then
    echo "No changes to commit."
    exit 0
fi

# Show changed files
echo "Changed files:"
git status --short

# Stage all changes
git add .

# Commit with timestamp
TIMESTAMP=$(date +"%Y-%m-%d %H:%M")
git commit -m "$MESSAGE

Updated: $TIMESTAMP
🤖 Generated with Claude Code"

# Push to GitHub
echo ""
echo "Pushing to GitHub..."
git push origin main

echo ""
echo "✅ Sync complete!"
