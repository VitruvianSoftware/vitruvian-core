#!/bin/bash
for pr in "$@"; do
    BRANCH=$(gh pr view $pr --json headRefName -q .headRefName)
    echo "Rebasing $BRANCH ($pr)..."
    git fetch origin
    git checkout $BRANCH
    git pull origin $BRANCH
    if ! git rebase origin/main; then
        echo "Conflict in $pr! Please fix manually."
        exit 1
    fi
    git push -f origin $BRANCH
    gh pr merge $pr --squash --admin
    git checkout main
    git pull origin main
done
