#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""Tests for agent_guard.py: the decision table, redaction, scope, modes, the hook I/O.

The table is built from what agents actually ran between 2026-10-09 and 10-16
(the design's inventory), plus every escape hatch the guard has to see through.
"""

import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from collections import Counter
from typing import Any, Dict
from unittest import mock

# The folder name has a hyphen, so it cannot be a package: import by path.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agent_guard as g  # noqa: E402

A, D = "allow", "deny"

# (command, decision, category or None, git-state key). {repo} is a fake
# vitruvian-core checkout, {wt} a linked worktree of it, {out} a directory
# outside it, {home} the fake HOME.
TABLE = [
    # --- read-only git: allowed ------------------------------------------------
    ("git status", A, None, ""),
    ("git status --porcelain", A, None, ""),
    ("git log --oneline -20", A, None, ""),
    ("git log origin/main..HEAD --format=%H", A, None, ""),
    ("git diff", A, None, ""),
    ("git diff --stat origin/main...HEAD", A, None, ""),
    ("git show HEAD:tools/ci/agent-fast-lane.sh", A, None, ""),
    ("git fetch origin main", A, None, ""),
    ("git fetch --prune", A, None, ""),
    ("git rev-parse --show-toplevel", A, None, ""),
    ("git rev-parse --abbrev-ref HEAD", A, None, ""),
    ("git ls-files -m", A, None, ""),
    ("git grep -n TODO -- '*.go'", A, None, ""),
    ("git blame -L 10,20 README.md", A, None, ""),
    ("git branch", A, None, ""),
    ("git branch --list 'feat/*'", A, None, ""),
    ("git branch -a --contains abc123", A, None, ""),
    ("git branch --show-current", A, None, ""),
    ("git branch -vv", A, None, ""),
    ("git worktree list", A, None, ""),
    ("git worktree list --porcelain", A, None, ""),
    ("git merge-base --is-ancestor abc origin/main", A, None, ""),
    ("git cat-file -p HEAD", A, None, ""),
    ("git config --get user.email", A, None, ""),
    ("git config user.name", A, None, ""),
    ("git config --list --show-origin", A, None, ""),
    ("git remote -v", A, None, ""),
    ("git remote get-url origin", A, None, ""),
    ("git stash list", A, None, ""),
    ("git stash show -p stash@{0}", A, None, ""),
    ("git tag -l 'vitruvian-v*'", A, None, ""),
    ("git tag", A, None, ""),
    ("git describe --tags", A, None, ""),
    ("git rev-list --count HEAD", A, None, ""),
    ("git for-each-ref refs/heads", A, None, ""),
    ("git pull --ff-only", A, None, "primary"),
    ("git apply --check fix.patch", A, None, ""),
    ("git checkout -- README.md", A, None, ""),
    ("git checkout README.md", A, None, ""),
    ("git checkout HEAD~1 -- src/main.go", A, None, ""),
    ("git restore src/main.go", A, None, ""),
    ("git --no-pager log -1", A, None, ""),
    ("git -C {repo} status", A, None, ""),
    ("/usr/bin/git log -3", A, None, ""),
    ("git commit --help", A, None, ""),
    ("git --version", A, None, ""),
    ("git reflog -10", A, None, ""),
    ("git shortlog -sn", A, None, ""),
    ("git ls-remote origin", A, None, ""),
    ("git range-diff a...b", A, None, ""),
    # --- read-only gh: allowed -------------------------------------------------
    ("gh pr view 3427 --json state", A, None, ""),
    ("gh pr list --author @me", A, None, ""),
    ("gh pr checks 3427", A, None, ""),
    ("gh pr diff 3427", A, None, ""),
    ("gh pr status", A, None, ""),
    ("gh run list --workflow ci.yaml", A, None, ""),
    ("gh run view 123 --log-failed", A, None, ""),
    ("gh run watch 123", A, None, ""),
    ("gh workflow list", A, None, ""),
    ("gh issue view 3418", A, None, ""),
    ("gh issue comment 3418 --body 'step 2 live'", A, None, ""),
    ("gh issue create --title x --body y", A, None, ""),
    ("gh api repos/VitruvianSoftware/vitruvian-core/pulls/3427", A, None, ""),
    ("gh api -X GET search/issues -f q=repo:x", A, None, ""),
    (
        "gh api --paginate repos/o/r/actions/runs --jq '.workflow_runs[].id'",
        A,
        None,
        "",
    ),
    ("gh api graphql -f query='query { viewer { login } }'", A, None, ""),
    (
        "gh api graphql -F owner=x -f query='{ repository(owner:$owner,name:\"r\"){ id } }'",
        A,
        None,
        "",
    ),
    ("gh auth status", A, None, ""),
    ("gh search prs --author @me", A, None, ""),
    ("gh release list", A, None, ""),
    ("gh repo view --json name", A, None, ""),
    ("gh --version", A, None, ""),
    # --- Bazel and ungoverned programs: allowed --------------------------------
    ("bazel test //...", A, None, ""),
    ("bazel run //tools/worktree -- feat/x", A, None, ""),
    ("bazel run //tools/git:commit -- -m 'feat: x' a.go", A, None, ""),
    ("bazel run //tools/agent-app -- pr-create --title x", A, None, ""),
    ("bazelisk build //apps/cli/devx/...", A, None, ""),
    ("aspect lint //tools/...", A, None, ""),
    ("bazel clean", A, None, ""),
    ("bazel run //tools/agent-guard:install -- --dry-run", A, None, ""),
    ("bazel run //tools/agent-guard:install -- --check", A, None, ""),
    ("cat README.md", A, None, ""),
    ("ls -la tools/", A, None, ""),
    ("jq .name package.json", A, None, ""),
    ("python3 -c 'import json; print(json.load(open(\"a.json\")))'", A, None, ""),
    ("rg -n agent-guard docs/", A, None, ""),
    ("docker ps", A, None, ""),
    ("rm -rf node_modules", A, None, ""),
    ("rm -rf {repo}/bazel-out/tmp", A, None, ""),
    ("rm -f /tmp/x.log", A, None, ""),
    ("cat <<EOF > notes.txt\ngit push\ngit commit -m x\nEOF", A, None, ""),
    ("echo 'git push is blocked'", A, None, ""),
    ("npm view react version", A, None, ""),
    ("pnpm why typescript", A, None, ""),
    ("npm outdated", A, None, ""),
    ("go version", A, None, ""),
    ("go env GOPATH", A, None, ""),
    ("go list -m -u all", A, None, ""),
    ("swift --version", A, None, ""),
    ("xcodebuild -version", A, None, ""),
    ("xcrun simctl list devices", A, None, ""),
    ("cargo metadata --format-version 1", A, None, ""),
    ("kubectl get pods -n backstage", A, None, ""),
    ("kubectl -n argocd describe app tabula", A, None, ""),
    ("kubectl logs -n backstage deploy/backstage --tail 50", A, None, ""),
    ("kubectl rollout status deploy/x -n y", A, None, ""),
    ("helm template ./chart", A, None, ""),
    ("helm list -A", A, None, ""),
    ("pulumi version", A, None, ""),
    ("pulumi stack ls", A, None, ""),
    ("command -v git", A, None, ""),
    ("gofmt --version", A, None, ""),
    ("cat ~/.local/state/agent-guard/log.jsonl | jq -c .", A, None, ""),
    ("tail -5 ~/.local/state/agent-guard/log.jsonl", A, None, ""),
    # --- git writes: blocked ---------------------------------------------------
    ("git add .", D, "git-commit", ""),
    ("git add -A && git commit -m 'feat: x'", D, "git-commit", ""),
    ("git commit -m 'fix: y'", D, "git-commit", ""),
    ("git commit --amend --no-edit", D, "git-commit", ""),
    ("git rm -r old/", D, "git-commit", ""),
    ("git mv a.go b.go", D, "git-commit", ""),
    ("git push -u origin feat/agent-guard", D, "git-push", ""),
    ("git push --force-with-lease", D, "git-push", ""),
    ("git rebase -q origin/main", D, "git-history", ""),
    ("git rebase -i HEAD~3", D, "git-history", ""),
    ("git reset --hard origin/main", D, "git-history", ""),
    ("git reset HEAD~1", D, "git-history", ""),
    ("git merge origin/main", D, "git-history", ""),
    ("git cherry-pick abc123", D, "git-history", ""),
    ("git revert HEAD", D, "git-history", ""),
    ("git pull", D, "git-history", "primary"),
    ("git pull --rebase", D, "git-history", "primary"),
    ("git pull --ff-only", D, "git-history", "worktree"),
    ("git tag v1.2.3", D, "git-history", ""),
    ("git tag -d v1.2.3", D, "git-history", ""),
    ("git stash", D, "git-stash", ""),
    ("git stash push -m wip", D, "git-stash", ""),
    ("git stash pop", D, "git-stash", ""),
    ("git checkout -b feat/x", D, "git-branch", ""),
    ("git checkout main", D, "git-branch", ""),
    ("git checkout --detach origin/main", D, "git-branch", ""),
    ("git switch -c feat/x", D, "git-branch", ""),
    ("git switch main", D, "git-branch", ""),
    ("git branch -D feat/old", D, "git-branch", ""),
    ("git branch -d feat/old", D, "git-branch", ""),
    ("git branch feat/new", D, "git-branch", ""),
    ("git branch -m old new", D, "git-branch", ""),
    ("git worktree add ../wt -b feat/x origin/main", D, "git-worktree", ""),
    ("git worktree add --detach $SP/rv abc123", D, "git-worktree", ""),
    ("git worktree remove --force ../wt", D, "git-worktree", ""),
    ("git worktree prune", D, "git-worktree", ""),
    ("git worktree lock ../wt --reason wip", D, "git-worktree", ""),
    ("git worktree unlock ../wt", D, "git-worktree", ""),
    ("git config user.email bot@example.com", D, "git-other", ""),
    ("git config --unset core.hooksPath", D, "git-other", ""),
    ("git remote add fork https://github.com/x/y", D, "git-other", ""),
    ("git apply fix.patch", A, None, ""),
    ("git clean -fdx", D, "git-other", ""),
    ("git gc --prune=now", D, "git-other", ""),
    ("git update-ref refs/heads/main abc", D, "git-other", ""),
    ("git am < 0001.patch", D, "git-history", ""),
    ("git bisect start", D, "git-history", ""),
    # --- escape hatches: still seen -------------------------------------------
    ("/usr/bin/git commit -m x", D, "git-commit", ""),
    ("git -C {repo} push", D, "git-push", ""),
    ("cd {out} && git -C {repo} push origin HEAD", D, "git-push", ""),
    ("cd {repo} && git push", D, "git-push", "out"),
    ("git -c user.name=x commit -m y", D, "git-commit", ""),
    ("git --no-pager -C . commit -m y", D, "git-commit", ""),
    ("git status; git push", D, "git-push", ""),
    ("git status || git push", D, "git-push", ""),
    ("git diff | git apply --index", D, "git-commit", ""),
    ("(git add . && git commit -m x)", D, "git-commit", ""),
    ("{ git add .; git commit -m x; }", D, "git-commit", ""),
    ("echo $(git push 2>&1)", D, "git-push", ""),
    ("echo `git push`", D, "git-push", ""),
    ('x="$(git commit -m y)"', D, "git-commit", ""),
    ("diff <(git push) /dev/null", D, "git-push", ""),
    ("bash -c 'git push origin HEAD'", D, "git-push", ""),
    ("sh -c \"git commit -m 'x'\"", D, "git-commit", ""),
    ("zsh -lc 'git stash'", D, "git-stash", ""),
    ("bash <<'EOF'\ngit push\nEOF", D, "git-push", ""),
    ("bash <<< 'git push'", D, "git-push", ""),
    ('eval "git push origin HEAD"', D, "git-push", ""),
    ("env GIT_AUTHOR_NAME=x git commit -m y", D, "git-commit", ""),
    ("GIT_EDITOR=true git rebase --continue", D, "git-history", ""),
    ("env -i PATH=/usr/bin git push", D, "git-push", ""),
    ("env -S 'git push'", D, "git-push", ""),
    ("nice -n 10 go test ./...", D, "go", ""),
    ("time go test ./...", D, "go", ""),
    ("timeout 300 go test ./...", D, "go", ""),
    ("timeout -s KILL 5m swift test", D, "swift", ""),
    ("nohup pnpm install &", D, "node", ""),
    ("command git push", D, "git-push", ""),
    ("exec git push", D, "git-push", ""),
    ("sudo -u james git push", D, "git-push", ""),
    ("caffeinate -i go test ./...", D, "go", ""),
    ("echo feat/old | xargs git branch -D", D, "git-branch", ""),
    ("ls | xargs -I{} git add {}", D, "git-commit", ""),
    ("find . -name '*.go' -exec gofmt -w {} \\;", D, "lint", ""),
    ("watch -n 30 gh run rerun 123", D, "gh-run", ""),
    ("if git diff --quiet; then :; else git commit -am x; fi", D, "git-commit", ""),
    ('for b in a b; do git branch -D "$b"; done', D, "git-branch", ""),
    ('while read b; do git push origin "$b"; done < branches.txt', D, "git-push", ""),
    ("git status &&\ngit push", D, "git-push", ""),
    ("git status \\\n && git push", D, "git-push", ""),
    ("uv run pytest tools/x", D, "pytest", ""),
    ("python3 -m pytest -q", D, "pytest", ""),
    ("python -m ruff check .", D, "lint", ""),
    ("direnv exec . go test ./...", D, "go", ""),
    ('git commit -m "unterminated', D, "git-commit", ""),
    # --- gh writes: blocked ----------------------------------------------------
    ("gh pr create --base main --title x --body-file b.md", D, "gh-pr", ""),
    ("gh pr edit 3345 --body-file b.md", D, "gh-pr", ""),
    ("gh pr comment 3345 --body ok", D, "gh-pr", ""),
    ("gh pr merge 84 --squash --auto", D, "gh-pr", ""),
    ("gh pr merge 84 --admin", D, "gh-pr", ""),
    ("gh pr ready 84", D, "gh-pr", ""),
    ("gh pr close 84", D, "gh-pr", ""),
    ("gh pr review 84 --approve", D, "gh-pr", ""),
    ("gh pr checkout 84", D, "git-branch", ""),
    ("gh -R VitruvianSoftware/vitruvian-core pr merge 9 --auto", D, "gh-pr", "out"),
    ("gh workflow run ci.yaml --ref main", D, "gh-run", ""),
    ("gh run rerun 123 --failed", D, "gh-run", ""),
    ("gh run cancel 123", D, "gh-run", ""),
    ("gh run delete 123", D, "gh-run", ""),
    ("gh workflow enable ci.yaml", D, "gh-run", ""),
    ("gh workflow disable ci.yaml", D, "gh-run", ""),
    ("gh run rerun 123 --job 456", D, "gh-run", ""),
    (
        "gh api -X PUT repos/VitruvianSoftware/vitruvian-core/pulls/1/merge",
        D,
        "gh-api",
        "",
    ),
    (
        "gh api --method=POST repos/{owner}/{repo}/issues/1/labels -f labels[]=x",
        D,
        "gh-api",
        "",
    ),
    ("gh api repos/:owner/:repo/issues/1/comments -f body=hi", D, "gh-api", ""),
    (
        "gh api -XDELETE repos/VitruvianSoftware/vitruvian-core/git/refs/heads/x",
        D,
        "gh-api",
        "",
    ),
    (
        "gh api graphql -f query='mutation { enablePullRequestAutoMerge(input:{}) { clientMutationId } }'",
        D,
        "gh-api",
        "",
    ),
    ("gh api graphql -f query=@-", D, "gh-api", ""),
    ("gh release create v1 --notes x", D, "gh-other", ""),
    ("gh secret set FOO --body bar", D, "gh-other", ""),
    ("gh label create x", D, "gh-other", ""),
    # --- dev toolchains: blocked -----------------------------------------------
    ("go test ./...", D, "go", ""),
    ("go vet ./...", D, "go", ""),
    ("go build -o /tmp/x ./cmd/x", D, "go", ""),
    ("go run ./tools/pipeline/plan", D, "go", ""),
    ("go mod tidy", D, "go", ""),
    ("go fmt ./...", D, "go", ""),
    ("swift build --build-tests", D, "swift", ""),
    ("swift test --filter Foo", D, "swift", ""),
    ("swift run nexus-agent", D, "swift", ""),
    ("xcodebuild -scheme X test", D, "xcode", ""),
    ("xcrun notarytool submit x.zip --wait", D, "xcode", ""),
    ("npm install", D, "node", ""),
    ("npm ci", D, "node", ""),
    ("npm test", D, "node", ""),
    ("npm run build", D, "node", ""),
    ("pnpm install --frozen-lockfile", D, "node", ""),
    ("pnpm add -D jest", D, "node", ""),
    ("pnpm --filter tabula-web test", D, "node", ""),
    ("pnpm dlx create-x", D, "node", ""),
    ("npx -y @anthropic-ai/foo", D, "node", ""),
    ("yarn", D, "node", ""),
    ("yarn add react", D, "node", ""),
    ("cargo test", D, "cargo", ""),
    ("cargo build --release", D, "cargo", ""),
    ("cargo publish", D, "cargo", ""),
    ("./gradlew assembleDebug", D, "gradle", ""),
    ("gradle build", D, "gradle", ""),
    ("pytest -q tools/", D, "pytest", ""),
    ("gofmt -l .", D, "lint", ""),
    ("gofmt -w x.go", D, "lint", ""),
    ("golangci-lint run ./...", D, "lint", ""),
    ("ruff check .", D, "lint", ""),
    ("eslint src", D, "lint", ""),
    ("prettier --write .", D, "lint", ""),
    ("shellcheck tools/x.sh", D, "lint", ""),
    ("actionlint", D, "actionlint", ""),
    ("actionlint .github/workflows/ci.yaml", D, "actionlint", ""),
    ("gitleaks git --log-opts=origin/main..HEAD", D, "secret-scan", ""),
    ("gitleaks detect --no-git", D, "secret-scan", ""),
    # --- infra and clusters: blocked -------------------------------------------
    ("pulumi up --yes", D, "iac", ""),
    ("pulumi destroy", D, "iac", ""),
    ("pulumi import gcp:x y z", D, "iac", ""),
    ("pulumi refresh -s dev", D, "iac", ""),
    ("pulumi preview -s dev-local", D, "iac", ""),
    ("terraform apply", D, "iac", ""),
    ("kubectl apply -f x.yaml", D, "kubectl", ""),
    ("kubectl delete pod x -n y", D, "kubectl", ""),
    ("kubectl patch deploy x -p '{}'", D, "kubectl", ""),
    ("kubectl edit cm x", D, "kubectl", ""),
    ("kubectl -n backstage exec -it deploy/backstage -- sh", D, "kubectl", ""),
    ("kubectl rollout restart deploy/x -n y", D, "kubectl", ""),
    ("kubectl scale deploy x --replicas=0", D, "kubectl", ""),
    ("helm install x ./chart", D, "helm", ""),
    ("helm upgrade --install x ./chart", D, "helm", ""),
    ("helm uninstall x", D, "helm", ""),
    # --- Bazel caches (blocked from anywhere) ----------------------------------
    ("rm -rf ~/Library/Caches/bazel", D, "bazel-cache", "out"),
    ("rm -rf ~/.cache/bazel", D, "bazel-cache", "out"),
    ("rm -rf $HOME/.cache/bazel/worktrees/feat-x", D, "bazel-cache", "out"),
    ("rm -fr /private/var/tmp/_bazel_james/abc", D, "bazel-cache", "out"),
    ("chmod -R u+w ~/.cache/bazel && rm -rf ~/.cache/bazel", D, "bazel-cache", "out"),
    ("find ~/.cache/bazel -mindepth 1 -delete", D, "bazel-cache", "out"),
    ("bazel clean --expunge", D, "bazel-cache", ""),
    ("bazel --output_user_root=/tmp/x build //...", D, "bazel-cache", ""),
    ("rm -rf {wt}", D, "git-worktree", "out"),
    # --- the guard itself (blocked from anywhere) ------------------------------
    ("bazel run //tools/agent-guard:install -- --uninstall", D, "guard-config", ""),
    ("bazel run //tools/agent-guard:install -- --mode all=off", D, "guard-config", ""),
    # Agents may install (install.py then checks the main checkout), check and
    # dry-run; anything else on the installer is James's.
    ("bazel run //tools/agent-guard:install", A, None, ""),
    ("bazel run //tools/agent-guard:install --", A, None, ""),
    ("bazel run @//tools/agent-guard:install", A, None, ""),
    ("bazelisk run //tools/agent-guard:install", A, None, ""),
    ("bazel run //tools/agent-guard:install -- --dry-run --check", A, None, ""),
    ("cd {repo}/tools/agent-guard && bazel run :install", A, None, ""),
    (
        "cd {repo}/tools/agent-guard && bazel run :install -- --uninstall",
        D,
        "guard-config",
        "",
    ),
    ("bazel run //tools/agent-guard:install -- --uninstall --dry-run", A, None, ""),
    ("bazel run //tools/agent-guard:install -- --dry-run --uninstall", A, None, ""),
    ("bazel run //tools/agent-guard:install -- --mode=all=off", D, "guard-config", ""),
    ("bazel run //tools/agent-guard:install -- --home /tmp/h", D, "guard-config", ""),
    (
        "bazel run //tools/agent-guard:install -- --workspace /tmp/w",
        D,
        "guard-config",
        "",
    ),
    ("bazel run //tools/agent-guard:install -- --check --force", D, "guard-config", ""),
    ("bazel run //tools/agent-guard:install extra", D, "guard-config", ""),
    ("bazel run //tools/agent-guard:install --config=ci", D, "guard-config", ""),
    (
        "bazel run --run_under='env -u CLAUDECODE' //tools/agent-guard:install",
        D,
        "guard-config",
        "",
    ),
    (
        "bazel run --script_path=/tmp/i.sh //tools/agent-guard:install",
        D,
        "guard-config",
        "",
    ),
    ("bazel --bazelrc=/tmp/rc run //tools/agent-guard:install", D, "guard-config", ""),
    ("env -u CLAUDECODE bazel run //tools/agent-guard:install", D, "guard-config", ""),
    ("bazel-bin/tools/agent-guard/install", D, "guard-config", ""),
    ("python3 tools/agent-guard/install.py --uninstall --dry-run", A, None, ""),
    # --- the backstop's user files: read freely, written only by the Edit tools
    ("echo '{}' > ~/.claude/settings.json", D, "guard-config", "out"),
    (
        "jq '.a=1' ~/.claude/settings.json > /tmp/s && mv /tmp/s ~/.claude/settings.json",
        D,
        "guard-config",
        "out",
    ),
    ("sed -i '' 's/agent-guard/x/' ~/.claude/settings.json", D, "guard-config", "out"),
    ("cp /tmp/h.json ~/.gemini/config/hooks.json", D, "guard-config", "out"),
    ("cp /tmp/hooks.json ~/.gemini/config/", D, "guard-config", "out"),
    ("tee ~/.gemini/config/hooks.json < /tmp/h.json", D, "guard-config", "out"),
    ("rm ~/.claude/settings.json", D, "guard-config", "out"),
    ("rm -rf ~/.gemini", D, "guard-config", "out"),
    ("mv ~/.claude/settings.json /tmp/s.json", D, "guard-config", "out"),
    ("perl -pi -e 's/x/y/' ~/.claude/settings.json", D, "guard-config", "out"),
    ("ln -sf /tmp/s.json ~/.claude/settings.json", D, "guard-config", "out"),
    (
        "python3 -c \"open('{home}/.claude/settings.json', 'w').write('{}')\"",
        D,
        "guard-config",
        "out",
    ),
    ("cat ~/.claude/settings.json", A, None, "out"),
    ("jq .hooks ~/.claude/settings.json", A, None, "out"),
    ("grep -n agent-guard ~/.gemini/config/hooks.json", A, None, "out"),
    ("cp ~/.claude/settings.json /tmp/backup.json", A, None, "out"),
    ("perl -ne 'print if /hook/' ~/.claude/settings.json", A, None, "out"),
    ("ls -la ~/.claude ~/.gemini/config", A, None, "out"),
    ("echo note > ~/.claude/notes.md", A, None, "out"),
    (
        "python3 -c \"print(open('{home}/.claude/settings.json').read())\"",
        A,
        None,
        "out",
    ),
    ("bazel run //tools/git:commit -- -m 'tools/agent-guard:install'", A, None, ""),
    (
        "sed -i '' s/enforce/off/ ~/.local/share/agent-guard/policy.json",
        D,
        "guard-config",
        "out",
    ),
    ("echo '{}' > ~/.local/share/agent-guard/policy.json", D, "guard-config", "out"),
    ("rm ~/.local/state/agent-guard/log.jsonl", D, "guard-config", "out"),
    (
        "cp /tmp/p.json $HOME/.local/share/agent-guard/policy.json",
        D,
        "guard-config",
        "out",
    ),
    # --- the guard's folders in HOME: a read or copy SOURCE is fine ------------
    ("cp -R ~/.local/share/agent-guard /tmp/scratch-ag", A, None, "out"),
    ("cp ~/.local/state/agent-guard/log.jsonl /tmp/log.jsonl", A, None, "out"),
    ("rsync -a ~/.local/share/agent-guard/ /tmp/ag/", A, None, "out"),
    ("cp /tmp/p.json ~/.local/share/agent-guard/", D, "guard-config", "out"),
    ("cp -t ~/.local/state/agent-guard /tmp/log.jsonl", D, "guard-config", "out"),
    ("mv ~/.local/share/agent-guard /tmp/ag", D, "guard-config", "out"),
    (
        "python3 -c \"import shutil; shutil.copytree('{home}/.local/share/agent-guard', '/tmp/ag')\"",
        A,
        None,
        "out",
    ),
    (
        "python3 -c \"print(open('{home}/.local/state/agent-guard/log.jsonl').read()[-200:])\"",
        A,
        None,
        "out",
    ),
    (
        "python3.15 -c \"import json; json.load(open('{home}/.local/share/agent-guard/policy.json'))\"",
        A,
        None,
        "out",
    ),
    (
        "python3 -c \"open('/tmp/x', 'w').write(open('{home}/.local/share/agent-guard/policy.json').read())\"",
        A,
        None,
        "out",
    ),
    (
        "python3 -c \"open('{home}/.local/share/agent-guard/policy.json', 'w').write('{}')\"",
        D,
        "guard-config",
        "out",
    ),
    (
        "python3 -c \"import shutil; shutil.rmtree('{home}/.local/share/agent-guard')\"",
        D,
        "guard-config",
        "out",
    ),
    (
        "python3 -c \"import shutil; shutil.copy('/tmp/p.json', '{home}/.local/share/agent-guard/policy.json')\"",
        D,
        "guard-config",
        "out",
    ),
    (
        "python3.15 -c \"import os; os.remove('{home}/.local/state/agent-guard/log.jsonl')\"",
        D,
        "guard-config",
        "out",
    ),
    (
        "python3 -c \"from pathlib import Path; Path('{home}/.local/share/agent-guard/policy.json').write_text('{}')\"",
        D,
        "guard-config",
        "out",
    ),
    (
        "python3 -c \"import shutil; shutil.copy('.claude/settings.json', '/tmp/s.json')\"",
        A,
        None,
        "",
    ),
    (
        "python3 -c \"import shutil; shutil.copy('/tmp/s.json', '.claude/settings.json')\"",
        D,
        "guard-config",
        "",
    ),
    # --- the checkout's hook files: they take effect before review -------------
    ("sed -i '' /agent-guard/d .claude/settings.json", D, "guard-config", ""),
    (
        "jq 'del(.hooks)' .claude/settings.json > /tmp/s && mv /tmp/s .claude/settings.json",
        D,
        "guard-config",
        "",
    ),
    ("echo '{}' > .agents/hooks.json", D, "guard-config", ""),
    ("echo '{}' >| .agents/hooks.json", D, "guard-config", ""),
    ("cat /tmp/x | tee .agents/hooks.json", D, "guard-config", ""),
    ("cp /tmp/hooks.json .agents/hooks.json", D, "guard-config", ""),
    ("cp /tmp/hooks.json .agents/", D, "guard-config", ""),
    ("cp -t .claude /tmp/settings.json", D, "guard-config", ""),
    ("rm .agents/hooks.json", D, "guard-config", ""),
    ("rm -rf .claude", D, "guard-config", ""),
    ("mv .agents /tmp/agents", D, "guard-config", ""),
    ("mv tools/agent-guard /tmp/ag", D, "guard-config", ""),
    ("chmod -R a-w tools", D, "guard-config", ""),
    ("echo 'exit 0' > tools/agent-guard/hook.sh", D, "guard-config", ""),
    ("perl -pi -e s/block/continue/ .claude/settings.json", D, "guard-config", ""),
    (
        "python3 -c \"open('.claude/settings.json', 'w').write('{}')\"",
        D,
        "guard-config",
        "",
    ),
    (
        "echo '{\"disableAllHooks\": true}' > .claude/settings.local.json",
        D,
        "guard-config",
        "",
    ),
    ("cd .claude && echo '{}' > settings.json", D, "guard-config", ""),
    ("echo '{}' > {wt}/.claude/settings.json", D, "guard-config", "out"),
    ("rm {repo}/.agents/hooks.json", D, "guard-config", "out"),
    ("echo 'exit 0' > .claude/block-queue-bypass.sh", D, "guard-config", ""),
    (
        "sed -i '' 's/exit 2/exit 0/' .claude/block-queue-bypass.sh",
        D,
        "guard-config",
        "",
    ),
    ("rm .claude/session-start.sh", D, "guard-config", ""),
    ("cp /tmp/x.sh .claude/kube-setup.sh", D, "guard-config", ""),
    ("chmod -x .claude/tailscale-up.sh", D, "guard-config", ""),
    ("echo x > .claude/new-hook.sh", D, "guard-config", ""),
    ("bash .claude/session-start.sh", A, None, ""),
    # The repo script session-start.sh runs that is still protected: the
    # build-cache configurator. (cloud-bootstrap.sh and profiles.tsv were
    # unprotected so an agent can change them in a PR the guard owner approves:
    # they stay behind the agent-guard-review ruleset.)
    ("echo 'exit 0' > tools/cloud-bootstrap/cloud-bootstrap.sh", A, None, ""),
    (
        "sed -i '' 's/exit 1/exit 0/' tools/cloud-bootstrap/cloud-bootstrap.sh",
        A,
        None,
        "",
    ),
    ("cp /tmp/x.sh tools/remote/setup.sh", D, "guard-config", ""),
    ("cat /tmp/x | tee tools/remote/setup.sh", D, "guard-config", ""),
    ("rm tools/remote/setup.sh", D, "guard-config", ""),
    ("rm -rf tools/cloud-bootstrap", A, None, ""),
    ("mv tools/remote /tmp/remote", D, "guard-config", ""),
    ("chmod -x tools/cloud-bootstrap/cloud-bootstrap.sh", A, None, ""),
    (
        "python3 -c \"open('tools/remote/setup.sh', 'w').write('')\"",
        D,
        "guard-config",
        "",
    ),
    (
        "echo x > {wt}/tools/cloud-bootstrap/cloud-bootstrap.sh",
        A,
        None,
        "out",
    ),
    ("cat tools/cloud-bootstrap/cloud-bootstrap.sh", A, None, ""),
    ("sed -n 1,40p tools/remote/setup.sh", A, None, ""),
    ("cp tools/remote/setup.sh /tmp/setup.sh", A, None, ""),
    ("bash tools/cloud-bootstrap/cloud-bootstrap.sh whoami", A, None, ""),
    ("bazel run //tools/cloud-bootstrap:whoami", A, None, ""),
    ("echo x >> tools/cloud-bootstrap/cloud-bootstrap_test.sh", A, None, ""),
    ("echo x > tools/remote/setup_test.sh", A, None, ""),
    # profiles.tsv decides which secrets session start fetches; changing it is
    # gated by the agent-guard-review ruleset, not by this local guard.
    ("echo x >> tools/cloud-bootstrap/profiles.tsv", A, None, ""),
    ("cp /tmp/p.tsv tools/cloud-bootstrap/profiles.tsv", A, None, ""),
    ("sed -i '' s/core/all/ tools/cloud-bootstrap/profiles.tsv", A, None, ""),
    ("mv tools/cloud-bootstrap/profiles.tsv /tmp/p.tsv", A, None, ""),
    ("rm tools/cloud-bootstrap/profiles.tsv", A, None, ""),
    ("cat tools/cloud-bootstrap/profiles.tsv", A, None, ""),
    ("awk '{print $1}' tools/cloud-bootstrap/profiles.tsv", A, None, ""),
    ("cp tools/cloud-bootstrap/profiles.tsv /tmp/p.tsv", A, None, ""),
    ("echo x > tools/cloud-bootstrap/README.md", A, None, ""),
    ("cat .claude/block-queue-bypass.sh", A, None, ""),
    ("echo x > .claude/sub/x.sh", A, None, ""),
    ("cat .claude/settings.json", A, None, ""),
    ("jq '.hooks.PreToolUse' .claude/settings.json", A, None, ""),
    ("git diff origin/main -- .claude/settings.json .agents/hooks.json", A, None, ""),
    ("git log -p -- tools/agent-guard/hook.sh", A, None, ""),
    ("printf '{}' | /bin/sh tools/agent-guard/hook.sh", A, None, ""),
    ("cp tools/agent-guard/hook.sh /tmp/hook.sh", A, None, ""),
    ("sed -n 1,20p tools/agent-guard/hook.sh", A, None, ""),
    ("diff .agents/hooks.json /tmp/hooks.json", A, None, ""),
    ("sed -i '' s/foo/bar/ tools/agent-guard/agent_guard.py", A, None, ""),
    ("echo '{}' > tools/agent-guard/policy.json", A, None, ""),
    ("mkdir -p .agents/rules && echo x > .agents/rules/x.md", A, None, ""),
    ("echo x > .claude/notes.md", A, None, ""),
    ("bazel test //tools/agent-guard/...", A, None, ""),
    (
        "bazel run //tools/git:commit -- -m 'cache in ~/.local/state/agent-guard/cache' tools/agent-guard/hook.sh",
        A,
        None,
        "",
    ),
    ("echo '{}' > /tmp/elsewhere/.claude/settings.json", A, None, "out"),
    # --- fetches that could move origin/main (hook.sh runs the guard from it) --
    ("git fetch", A, None, ""),
    ("git fetch origin", A, None, ""),
    ("git fetch -q origin main", A, None, ""),
    ("git fetch --prune origin", A, None, ""),
    ("git fetch --all --prune", A, None, ""),
    ("git fetch origin refs/pull/12/head", A, None, ""),
    ("git fetch https://github.com/evil/fork main", A, None, ""),
    ("git fetch --depth 1 origin main", A, None, ""),
    (
        "git fetch https://github.com/evil/fork +main:refs/remotes/origin/main",
        D,
        "git-other",
        "",
    ),
    ("git fetch origin +refs/heads/x:refs/remotes/origin/main", D, "git-other", ""),
    ("git fetch evil main:main", D, "git-other", ""),
    ("git fetch origin main:refs/heads/main", D, "git-other", ""),
    ("git fetch upstream '+refs/heads/*:refs/remotes/origin/*'", D, "git-other", ""),
    ("git fetch -q --depth=1 origin pr:refs/heads/pr", D, "git-other", ""),
    (
        "git fetch https://github.com/evil/fork main --refmap='+refs/heads/*:refs/remotes/origin/*'",
        D,
        "git-other",
        "",
    ),
    (
        "git -c remote.origin.url=https://github.com/evil/fork fetch origin",
        D,
        "git-other",
        "",
    ),
    (
        "git -c url.https://github.com/evil/.insteadOf=https://github.com/VitruvianSoftware/ fetch",
        D,
        "git-other",
        "",
    ),
    ("git -C {wt} fetch https://x/y main:refs/remotes/origin/main", D, "git-other", ""),
    (
        "git pull --ff-only evil main:refs/remotes/origin/main",
        D,
        "git-other",
        "primary",
    ),
    (
        "git pull --ff-only --log evil main:refs/remotes/origin/main",
        D,
        "git-other",
        "primary",
    ),
    ("git fetch -- evil main:refs/remotes/origin/main", D, "git-other", ""),
    # --- in-progress merge / rebase / cherry-pick ------------------------------
    ("git merge --continue", A, None, "merging"),
    ("git merge --abort", A, None, "merging"),
    ("git merge --continue", D, "git-history", ""),
    ("git merge --abort", D, "git-history", ""),
    ("git rebase --continue", A, None, "rebasing"),
    ("git rebase --abort", A, None, "rebasing"),
    ("git rebase --skip", A, None, "rebasing"),
    ("GIT_EDITOR=true git rebase --continue", A, None, "rebasing"),
    ("git rebase --continue", D, "git-history", ""),
    ("git rebase --abort", D, "git-history", ""),
    ("git rebase --skip", D, "git-history", ""),
    ("git rebase --continue", D, "git-history", "merging"),
    ("git cherry-pick --continue", A, None, "picking"),
    ("git cherry-pick --abort", A, None, "picking"),
    ("git cherry-pick --continue", D, "git-history", ""),
    ("git cherry-pick --abort", D, "git-history", ""),
    ("git add src/conflicted.go", A, None, "merging"),
    ("git add src/conflicted.go", A, None, "rebasing"),
    ("git add src/conflicted.go", A, None, "picking"),
    ("git add src/conflicted.go", D, "git-commit", ""),
    ("git add src/other.go", D, "git-commit", "merging"),
    ("git add .", D, "git-commit", "merging"),
    ("git add -A", D, "git-commit", "rebasing"),
    ("git commit --no-edit", D, "git-commit", "merging"),
    ("git commit", D, "git-commit", "merging"),
    # --- heredoc bodies are data, even with apostrophes (fix round 1) ---------
    (
        "gh issue comment 3418 --body \"$(cat <<'EOF'\nIt didn't break.\nRan `go test ./...`\nEOF\n)\"",
        A,
        None,
        "",
    ),
    (
        "speaker-broadcast \"$(cat <<'EOF'\nPR's merged; git push done\nEOF\n)\"",
        A,
        None,
        "",
    ),
    (
        "bazel run //tools/git:commit -- -m \"$(cat <<'EOF'\nfix: don't git push from scripts\n\nIt's npm test's job.\nEOF\n)\"",
        A,
        None,
        "",
    ),
    (
        'bazel run //tools/git:commit -- -m "$(cat <<EOF\nfeat: it\'s done\nRan \\`go test\\` and \\$(npm test)\nEOF\n)"',
        A,
        None,
        "",
    ),
    (
        "gh pr view 1 --json body -q \"$(cat <<-'EOF'\n\tquote \" and ' and `git push` and $(git commit)\n\tEOF\n)\"",
        A,
        None,
        "",
    ),
    (
        'speaker-broadcast "$(cat <<"END"\nwe\'ll npm test then go test; git push\nEND\n)"',
        A,
        None,
        "",
    ),
    ("x=$(cat <<'EOF'\nit's `git push` time\nEOF\n); echo \"$x\"", A, None, ""),
    (
        "gh issue comment 1 --body \"$(cat <<'EOF'\ndidn't\nEOF\n)\" && git push",
        D,
        "git-push",
        "",
    ),
    ("echo \"$(cat <<'EOF'\nwon't\nEOF\n)\"; go test ./...", D, "go", ""),
    ("bash <<'EOF'\nit's\ngit push\nEOF", D, "git-push", ""),
    ('cat <<EOF | sh\ngit commit -m "don\'t"\nEOF', A, None, ""),
    ("echo $((1 << 2)) && git status", A, None, ""),
    # --- gh aimed at another repository is out of scope ----------------------
    ("gh -R VitruvianSoftware/devx pr merge 3 --squash --auto", A, None, ""),
    ("gh --repo x/y pr create --title t --body b", A, None, ""),
    (
        "gh pr comment https://github.com/VitruvianSoftware/devx/pull/12 --body ok",
        A,
        None,
        "",
    ),
    (
        "gh api repos/VitruvianSoftware/homelab/issues/5/comments -f body=hi",
        A,
        None,
        "",
    ),
    ("gh api -X PUT /repos/someone/else/pulls/1/merge", A, None, ""),
    ("gh workflow run ci.yaml -R VitruvianSoftware/nexus-agent", A, None, ""),
    ("gh -R VitruvianSoftware/vitruvian-core pr merge 9 --auto", D, "gh-pr", ""),
    (
        "gh api repos/VitruvianSoftware/vitruvian-core/issues/1/labels -f labels[]=x",
        D,
        "gh-api",
        "out",
    ),
    ("gh api repos/{owner}/{repo}/pulls/1/merge -X PUT", D, "gh-api", ""),
    (
        "gh pr merge https://github.com/VitruvianSoftware/vitruvian-core/pull/3 --auto",
        D,
        "gh-pr",
        "out",
    ),
    # --- only :install is the installer ---------------------------------------
    ("bazel run //tools/agent-guard -- --version", A, None, ""),
    ("bazel run //tools/agent-guard < payload.json", A, None, ""),
    ("bazel run //tools/agent-guard:install -- --help", A, None, ""),
    # --- git apply and git clean -n -------------------------------------------
    ("git apply --3way fix.patch", D, "git-commit", ""),
    ("git apply -p1 < fix.patch", A, None, ""),
    ("git clean -n", A, None, ""),
    ("git clean -nd", A, None, ""),
    ("git clean --dry-run -x", A, None, ""),
    ("git clean -f", D, "git-other", ""),
    # --- running the installer around the guard -------------------------------
    ("python3 tools/agent-guard/install.py", D, "guard-config", ""),
    ("python3 tools/agent-guard/install.py --uninstall", D, "guard-config", ""),
    ("env -u CLAUDECODE python3 tools/agent-guard/install.py", D, "guard-config", ""),
    ("bazel-bin/tools/agent-guard/install --mode all=off", D, "guard-config", ""),
    ("unset CLAUDECODE; bazel run //tools/agent-guard:install", D, "guard-config", ""),
    (
        "env -u ANTIGRAVITY_AGENT bazel run //tools/agent-guard:install -- --dry-run",
        D,
        "guard-config",
        "",
    ),
    ("python3 tools/agent-guard/install.py --dry-run", A, None, ""),
    ("bazel-bin/tools/agent-guard/install --check", A, None, ""),
    ("cat tools/agent-guard/install.py", A, None, ""),
    ("env -u CLAUDECODE go version", A, None, ""),
    # --- fix round 2: the reviewer's cases5, marker hiding, unquoted heredocs ---
    ("grep -n 'unset CLAUDECODE' tools/agent-guard/install.py", A, None, ""),
    ("rg -n 'CLAUDECODE=' tools/agent-guard/", A, None, ""),
    ("bazel test //tools/agent-guard/... --test_env=CLAUDECODE= ", A, None, ""),
    (
        "git diff origin/main -- tools/agent-guard/ | grep -n 'env -u CLAUDECODE'",
        A,
        None,
        "",
    ),
    ("sed -n '1,40p' tools/agent-guard/README.md", A, None, ""),
    ("python3 -m py_compile tools/agent-guard/install.py", A, None, ""),
    ("python3 -I tools/agent-guard/install.py --dry-run", A, None, ""),
    ("python3 tools/agent-guard/install.py --check", A, None, ""),
    ("bazel test //tools/agent-guard:install_test", A, None, ""),
    ("CLAUDECODE= bazel run //tools/agent-guard:install", D, "guard-config", ""),
    ("gh pr merge 1 --auto -R VitruvianSoftware/vitruvian-core", D, "gh-pr", ""),
    (
        "gh pr merge https://github.com/VitruvianSoftware/vitruvian-core/pull/1 --auto",
        D,
        "gh-pr",
        "",
    ),
    (
        "gh api -X POST repos/VitruvianSoftware/vitruvian-core/issues/1/comments -f body=x",
        D,
        "gh-api",
        "",
    ),
    (
        "gh api -X POST repos/{owner}/{repo}/issues/1/comments -f body=x",
        D,
        "gh-api",
        "",
    ),
    ("gh pr merge 5 --auto --repo=VitruvianSoftware/devx", A, None, ""),
    (
        "gh pr merge https://github.com/VitruvianSoftware/devx/pull/5 --auto",
        A,
        None,
        "",
    ),
    ("echo $((1 << 2))", A, None, ""),
    ('x=$(cat <<EOF\nit\'s $(date)\nEOF\n); echo "$x"', A, None, ""),
    (
        "echo \"$(cat <<'A'\nfirst it's\nA\n)\" \"$(cat <<'B'\nsecond (unbalanced\nB\n)\"",
        A,
        None,
        "",
    ),
    (
        "bazel run //tools/git:commit -- -m \"$(cat <<'EOF'\nfix: it's done\n\ngit push and go test both pass; `npm test` too\nEOF\n)\"",
        A,
        None,
        "",
    ),
    ("echo \"$(cat <<'EOF'\nhi\nEOF\n)\" && git push", D, "git-push", ""),
    ('gh issue comment 1 --body "$(cat <<EOF\n$(git push)\nEOF\n)"', D, "git-push", ""),
    ("rg -n 'ANTIGRAVITY_AGENT=' tools/agent-guard/", A, None, ""),
    ("echo 'env -i bazel run //tools/agent-guard:install' >> notes.txt", A, None, ""),
    (
        "env -u CLAUDECODE bazel run //tools/agent-guard:install -- --dry-run",
        D,
        "guard-config",
        "",
    ),
    (
        "env --unset=CLAUDECODE bazel run //tools/agent-guard:install -- --check",
        D,
        "guard-config",
        "",
    ),
    (
        "env -uCLAUDECODE python3 tools/agent-guard/install.py --dry-run",
        D,
        "guard-config",
        "",
    ),
    (
        "env -i bazel run //tools/agent-guard:install -- --dry-run",
        D,
        "guard-config",
        "",
    ),
    (
        "unset CLAUDECODE; bazel run //tools/agent-guard:install -- --check",
        D,
        "guard-config",
        "",
    ),
    (
        "export -n CLAUDECODE && python3 tools/agent-guard/install.py --dry-run",
        D,
        "guard-config",
        "",
    ),
    (
        "ANTIGRAVITY_AGENT= bazel run //tools/agent-guard:install -- --dry-run",
        D,
        "guard-config",
        "",
    ),
    ("GEMINI_CLI= python3 tools/agent-guard/install.py --check", D, "guard-config", ""),
    (
        "bash -c 'unset CLAUDECODE; bazel run //tools/agent-guard:install -- --dry-run'",
        D,
        "guard-config",
        "",
    ),
    ("cat <<EOF\nRan `git push` for you\nEOF", D, "git-push", ""),
    ("cat <<EOF\nRan \\`git push\\` and \\$(go test)\nEOF", A, None, ""),
    ("cat <<'EOF'\nRan `git push` and $(go test)\nEOF", A, None, ""),
    ("cat <<\\EOF\n$(git push)\nEOF", A, None, ""),
    (
        'gh pr create --body "$(cat <<EOF\nSummary: $(git log --oneline -1)\nEOF\n)"',
        D,
        "gh-pr",
        "",
    ),
]


# Too many commands to check in time: refused inside the repo (generated here
# rather than spelled out). Real commands have tens; the cap is 20,000.
TABLE += [
    ("true; " * 25000, D, "oversize", ""),
    ("echo `x`" * 25000, D, "oversize", ""),
    ("true; " * 5000 + "git status", A, None, ""),
    ("true; " * 5000 + "git push", D, "git-push", ""),
]


def _git_state(repo, wt):
    conflicted = [os.path.join(repo, "src", "conflicted.go")]
    states = {
        "": g.GitState(primary=True),
        "primary": g.GitState(primary=True),
        "worktree": g.GitState(primary=False),
        "merging": g.GitState(merge=True, unmerged=conflicted),
        "rebasing": g.GitState(rebase=True, unmerged=conflicted),
        "picking": g.GitState(cherry_pick=True, unmerged=conflicted),
        "out": g.GitState(primary=True),
    }
    return states


class Fixture(object):
    def __init__(self):
        # Not under TEST_TMPDIR: inside Bazel that sits below an execroot whose
        # MODULE.bazel would make the "outside" directory look inside.
        self.tmp = tempfile.mkdtemp(
            prefix="agent-guard-test-",
            dir="/tmp" if os.access("/tmp", os.W_OK) else None,
        )
        self.home = os.path.join(self.tmp, "home")
        self.repo = os.path.join(self.tmp, "vitruvian-core")
        self.wt = os.path.join(self.tmp, "vitruvian-core-worktrees", "feat-x")
        self.out = os.path.join(self.tmp, "elsewhere")
        for d in (self.home, self.out, os.path.join(self.repo, "src"), self.wt):
            os.makedirs(d)
        for root in (self.repo, self.wt):
            with open(os.path.join(root, "MODULE.bazel"), "w") as fh:
                fh.write('module(\n    name = "vitruvian_core",\n)\n')
            with open(os.path.join(root, "README.md"), "w") as fh:
                fh.write("hi\n")
        os.makedirs(os.path.join(self.repo, ".git"))
        with open(os.path.join(self.wt, ".git"), "w") as fh:
            fh.write("gitdir: %s/.git/worktrees/feat-x\n" % self.repo)
        with open(os.path.join(self.repo, "src", "main.go"), "w") as fh:
            fh.write("package main\n")
        self.states = _git_state(self.repo, self.wt)
        g._scope_cache.clear()
        g._root_cache.clear()
        if g.repo_root_of(self.out) is not None:
            raise AssertionError(
                "fixture's outside dir %s is inside a vitruvian-core checkout"
                % self.out
            )

    def fmt(self, s):
        return (
            s.replace("{repo}", self.repo)
            .replace("{wt}", self.wt)
            .replace("{out}", self.out)
            .replace("{home}", self.home)
        )

    def run(self, command, key="", modes=None):
        cwd = self.out if key == "out" else self.repo
        state = self.states[key]
        return g.evaluate(
            self.fmt(command),
            cwd,
            modes=modes,
            home=self.home,
            git_state=lambda _d: state,
        )

    def close(self):
        shutil.rmtree(self.tmp, ignore_errors=True)


class DecisionTableTest(unittest.TestCase):
    """Command shapes. The fixture is not a real git checkout, so whether the
    installer there is origin/main's is taken as yes here; InstallerSourceTest
    checks that part against a real one."""

    @classmethod
    def setUpClass(cls):
        cls.fx = Fixture()
        cls._patch = mock.patch.object(g, "installer_problem", return_value="")
        cls._patch.start()

    @classmethod
    def tearDownClass(cls):
        cls._patch.stop()
        cls.fx.close()

    def test_table_is_big_enough(self):
        self.assertGreaterEqual(len(TABLE), 150)

    def test_every_row(self):
        failures = []
        for command, want, cat, key in TABLE:
            d = self.fx.run(command, key)
            if d.decision != want or d.category != cat:
                failures.append(
                    "%r [%s]: want %s/%s, got %s/%s"
                    % (command, key or "-", want, cat, d.decision, d.category)
                )
        self.assertEqual(failures, [], "\n" + "\n".join(failures))

    def test_every_category_has_a_blocked_row(self):
        covered = {cat for _c, want, cat, _k in TABLE if want == D}
        self.assertEqual(set(g.CATEGORIES) - covered, set())

    def test_summary(self):
        # Printed so the test log carries the per-category counts.
        counts = Counter(cat or "allowed" for _c, _w, cat, _k in TABLE)
        sys.stderr.write("\ndecision table: %d rows\n" % len(TABLE))
        for cat, n in sorted(counts.items()):
            sys.stderr.write("  %-14s %d\n" % (cat, n))

    def test_messages_name_the_replacement(self):
        cases = {
            "git commit -m x": "bazel run //tools/git:commit",
            "git push": "bazel run //tools/git:push",
            "git rebase origin/main": "bazel run //tools/git:sync",
            "git worktree add ../x -b y": "bazel run //tools/worktree -- <branch>",
            "git worktree add --detach /tmp/x HEAD": "--detach <ref>",
            "git worktree lock ../x": "--lock",
            "git worktree prune": "--prune",
            "gh pr create": "bazel run //tools/agent-app -- pr-create",
            "gitleaks detect": "bazel run //tools/secret-scan",
            "actionlint": "bazel run //tools/ci:actionlint",
            "rm -rf ~/.cache/bazel": "bazel run //tools/bazel-cache:gc",
            "go test ./...": "bazel test",
            "prettier --write .": "bazel run //tools/format",
            "kubectl apply -f x.yaml": "//tools/gitops",
            "gh run rerun 1 --failed": "bazel run //tools/agent-app -- run-rerun <run-id>",
            "gh run cancel 1": "bazel run //tools/agent-app -- run-cancel <run-id>",
            "gh workflow run ci.yaml": "bazel run //tools/agent-app -- workflow-run <file.yaml>",
        }
        for command, needle in cases.items():
            msg = self.fx.run(command).message
            self.assertIn(needle, msg, command)
            self.assertIn("guardrail", msg, command)

    def test_merges_point_at_pr_enqueue(self):
        msg = self.fx.run("gh pr merge 3 --squash --auto").message
        self.assertIn("bazel run //tools/agent-app -- pr-enqueue", msg)
        self.assertIn("not in this checkout yet", msg)

    def test_message_says_when_there_is_no_target(self):
        msg = self.fx.run("git reset --hard HEAD~1").message
        self.assertIn("no target for it yet", msg)
        self.assertIn("James", msg)

    def test_run_commands_point_at_agent_app(self):
        # agent-app has run-rerun, run-cancel and workflow-run (wren only);
        # deleting runs and enabling or disabling workflows still have no target.
        for command in ("gh run rerun 1", "gh run cancel 1", "gh workflow run ci.yaml"):
            msg = self.fx.run(command).message
            self.assertIn("//tools/agent-app --", msg, command)
            self.assertIn("Only wren's App has Actions write", msg, command)
            self.assertNotIn("no target for it yet", msg, command)
        self.assertIn(
            "workflow-allowlist.txt", self.fx.run("gh workflow run ci.yaml").message
        )
        for command in (
            "gh run delete 1",
            "gh workflow enable ci.yaml",
            "gh workflow disable ci.yaml",
        ):
            msg = self.fx.run(command).message
            self.assertIn("no target for it yet", msg, command)
            self.assertIn(
                "nothing that deletes runs or enables or disables", msg, command
            )

    def test_pending_target_is_flagged_until_it_lands(self):
        msg = self.fx.run("git push").message
        self.assertIn("not in this checkout yet", msg)
        os.makedirs(os.path.join(self.fx.repo, "tools", "git"))
        with open(os.path.join(self.fx.repo, "tools", "git", "BUILD"), "w") as fh:
            fh.write('sh_binary(name = "push")\n')
        try:
            msg = self.fx.run("git push").message
            self.assertNotIn("not in this checkout yet", msg)
        finally:
            shutil.rmtree(os.path.join(self.fx.repo, "tools"))

    def test_merge_commit_points_at_concluding_merge(self):
        msg = self.fx.run("git commit", "merging").message
        self.assertIn("//tools/git:commit", msg)
        self.assertIn("concludes", msg)


GIT_TEST_ENV = {
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@e",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@e",
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_NOSYSTEM": "1",
}


class InstallerSourceTest(unittest.TestCase):
    """An agent may run the installer only from a checkout where install.py,
    agent_guard.py and BUILD are origin/main's and no bazelrc sets run_under:
    an edited installer would otherwise run with James's HOME."""

    def setUp(self):
        self.tmp = os.path.realpath(
            tempfile.mkdtemp(
                prefix="agent-guard-installer-",
                dir="/tmp" if os.access("/tmp", os.W_OK) else None,
            )
        )
        self.repo = os.path.join(self.tmp, "vitruvian-core")
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home)
        files = {
            "MODULE.bazel": 'module(name = "vitruvian_core")\n',
            ".bazelrc": "try-import %workspace%/user.bazelrc\nbuild --jobs=4\n"
            "# run_under in a comment is fine\n",
            "tools/agent-guard/install.py": "print('installer')\n",
            "tools/agent-guard/agent_guard.py": "# guard\n",
            "tools/agent-guard/BUILD": 'py_binary(name = "install", main = "install.py")\n',
        }
        for rel, text in files.items():
            self.write(rel, text)
        self.git("init", "-q", "-b", "main")
        self.git("add", "-A")
        self.git("commit", "-qm", "init", "--no-gpg-sign")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        g._scope_cache.clear()
        g._root_cache.clear()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)
        g._scope_cache.clear()
        g._root_cache.clear()

    def write(self, rel, text, root=None):
        path = os.path.join(root or self.repo, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as fh:
            fh.write(text)

    def git(self, *args, cwd=None):
        subprocess.run(
            ["git", "-C", cwd or self.repo] + list(args),
            env=dict(os.environ, **GIT_TEST_ENV),
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    def decide(self, command, cwd=None):
        return g.evaluate(
            command,
            cwd or self.repo,
            home=self.home,
            git_state=lambda _d: g.GitState(),
        )

    COMMANDS = (
        "bazel run //tools/agent-guard:install",
        "bazel run //tools/agent-guard:install -- --check",
        "bazel run //tools/agent-guard:install -- --dry-run",
        "bazel run //tools/agent-guard:install -- --uninstall --dry-run",
        "python3 tools/agent-guard/install.py --check",
        "bazel-bin/tools/agent-guard/install --dry-run",
    )

    def assert_all(self, want, cwd=None, needle=""):
        for command in self.COMMANDS:
            d = self.decide(command, cwd)
            self.assertEqual(d.decision, want, "%s: %s" % (command, d.message))
            if want == D:
                self.assertEqual(d.category, "guard-config")
                self.assertIn(needle, d.message, command)

    def test_allowed_when_the_installer_is_origin_mains(self):
        self.assertEqual(g.installer_problem(self.repo, self.home), "")
        self.assert_all(A)

    def test_an_edited_install_py_is_refused(self):
        self.write("tools/agent-guard/install.py", "print('anything I like')\n")
        self.assert_all(
            D, needle="tools/agent-guard/install.py in %s differs" % self.repo
        )

    def test_an_edited_build_or_guard_is_refused(self):
        for rel in ("tools/agent-guard/BUILD", "tools/agent-guard/agent_guard.py"):
            self.write(rel, "# changed\n")
            self.assert_all(D, needle=rel)
            self.git("checkout", "--", rel)
        self.assert_all(A)

    def test_a_committed_but_unmerged_edit_is_refused(self):
        self.write("tools/agent-guard/install.py", "print('mine')\n")
        self.git("commit", "-qam", "mine", "--no-gpg-sign")
        self.assert_all(D, needle="differs from origin/main's")

    def test_an_edited_installer_in_a_worktree_is_refused_there_only(self):
        wt = os.path.join(self.tmp, "vitruvian-core-worktrees", "feat-x")
        self.git("worktree", "add", "-q", "--detach", wt)
        self.write("tools/agent-guard/install.py", "print('mine')\n", root=wt)
        self.assert_all(D, cwd=wt, needle="install.py in %s differs" % wt)
        self.assert_all(A)

    def test_no_origin_main_is_refused(self):
        self.git("update-ref", "-d", "refs/remotes/origin/main")
        self.assert_all(D, needle="origin/main or its installer cannot be read")

    def test_run_under_in_any_bazelrc_is_refused(self):
        self.write("user.bazelrc", "run --run_under='env -u CLAUDECODE'\n")
        self.assert_all(D, needle="user.bazelrc sets run_under")
        os.remove(os.path.join(self.repo, "user.bazelrc"))
        self.write(".bazelrc", "run --script_path=/tmp/x.sh\n", root=self.home)
        self.assert_all(D, needle=".bazelrc sets run_under or script_path")

    def test_outside_a_checkout_is_refused(self):
        d = self.decide("bazel run //tools/agent-guard:install", cwd=self.home)
        self.assertEqual(d.decision, D, d.message)
        self.assertIn("not run from inside a vitruvian-core checkout", d.message)


class ScopeTest(unittest.TestCase):
    def setUp(self):
        self.fx = Fixture()

    def tearDown(self):
        self.fx.close()

    def test_oversize_outside_is_allowed(self):
        d = self.fx.run("true; " * 25000, "out")
        self.assertEqual(d.decision, "allow")

    def test_outside_vitruvian_core_is_allowed(self):
        for command in (
            "git push",
            "git commit -am x",
            "go test ./...",
            "pnpm install",
            "gh pr merge 1 --auto",
            "kubectl apply -f x",
        ):
            d = self.fx.run(command, "out")
            self.assertEqual(d.decision, "allow", command)
            self.assertEqual(d.scope, "outside", command)

    def test_other_bazel_repo_is_outside(self):
        other = os.path.join(self.fx.tmp, "abrialcode")
        os.makedirs(other)
        with open(os.path.join(other, "MODULE.bazel"), "w") as fh:
            fh.write('module(name = "abrialcode")\n')
        d = g.evaluate(
            "git push", other, home=self.fx.home, git_state=lambda _d: g.GitState()
        )
        self.assertEqual(d.decision, "allow")

    def test_worktree_and_subdirectory_are_inside(self):
        for cwd in (self.fx.wt, os.path.join(self.fx.repo, "src")):
            d = g.evaluate(
                "git push", cwd, home=self.fx.home, git_state=lambda _d: g.GitState()
            )
            self.assertEqual(d.decision, "deny", cwd)
            self.assertEqual(d.scope, "inside")

    def test_cd_out_of_the_repo_leaves_scope(self):
        d = self.fx.run("cd {out} && git push")
        self.assertEqual(d.decision, "allow")

    def test_inside_allowed_is_reported_inside(self):
        self.assertEqual(self.fx.run("git status").scope, "inside")

    def test_unknown_location_is_enforced(self):
        def run(command):
            return g.evaluate(
                command,
                g.UNKNOWN_CWD,
                home=self.fx.home,
                git_state=lambda _d: g.GitState(primary=True),
                cwd_known=False,
            )

        for command in ("go vet ./...", "git push", "cd /tmp && git commit -m x"):
            d = run(command)
            self.assertEqual((d.decision, d.scope), ("deny", "unknown"), command)
        self.assertEqual(run("true; " * 25000).decision, "deny")
        d = run("git status")
        self.assertEqual((d.decision, d.scope), ("allow", "unknown"))
        self.assertEqual(run("gh pr merge 1 -R someone/else").decision, "allow")


class ModesTest(unittest.TestCase):
    def setUp(self):
        self.fx = Fixture()

    def tearDown(self):
        self.fx.close()

    def test_enforce_warn_off(self):
        base = {c: "enforce" for c in g.CATEGORIES}
        self.assertEqual(self.fx.run("git push", modes=base).decision, "deny")
        warn = dict(base, **{"git-push": "warn"})
        d = self.fx.run("git push", modes=warn)
        self.assertEqual(d.decision, "warn")
        self.assertEqual(d.category, "git-push")
        off = dict(base, **{"git-push": "off"})
        self.assertEqual(self.fx.run("git push", modes=off).decision, "allow")

    def test_a_later_enforced_segment_beats_an_earlier_warning(self):
        modes = dict({c: "enforce" for c in g.CATEGORIES}, **{"git-commit": "warn"})
        d = self.fx.run("git commit -m x && git push", modes=modes)
        self.assertEqual((d.decision, d.category), ("deny", "git-push"))

    def test_policy_file(self):
        path = os.path.join(self.fx.tmp, "policy.json")
        with open(path, "w") as fh:
            json.dump(
                {
                    "default_mode": "warn",
                    "categories": {"go": {"mode": "off"}, "git-push": "enforce"},
                },
                fh,
            )
        modes = g.load_policy(path)
        self.assertEqual(modes["go"], "off")
        self.assertEqual(modes["git-push"], "enforce")
        self.assertEqual(modes["git-commit"], "warn")

    def test_broken_or_missing_policy_enforces_everything(self):
        path = os.path.join(self.fx.tmp, "broken.json")
        with open(path, "w") as fh:
            fh.write("{not json")
        for p in (path, os.path.join(self.fx.tmp, "missing.json")):
            self.assertEqual(set(g.load_policy(p).values()), {"enforce"})

    def test_shipped_policy_enforces_every_category(self):
        modes = g.load_policy(g.default_policy_path())
        self.assertEqual(set(modes), set(g.CATEGORIES))
        self.assertEqual(set(modes.values()), {"enforce"})
        with open(g.default_policy_path()) as fh:
            self.assertEqual(set(json.load(fh)["categories"]), set(g.CATEGORIES))


class PerformanceTest(unittest.TestCase):
    """The whole hook, end to end, must answer well inside its 10 s timeout.

    The command-tool entry fails closed, so a slow answer is a refusal. Each
    case runs main() on a full payload: parse, decide, redact and log.
    """

    LIMIT = 1.0

    @classmethod
    def setUpClass(cls):
        cls.fx = Fixture()
        cls._old = os.environ.get("AGENT_GUARD_HOME")
        os.environ["AGENT_GUARD_HOME"] = cls.fx.home

    @classmethod
    def tearDownClass(cls):
        if cls._old is None:
            os.environ.pop("AGENT_GUARD_HOME", None)
        else:
            os.environ["AGENT_GUARD_HOME"] = cls._old
        cls.fx.close()

    def timed(self, name, command, cwd=None):
        payload = json.dumps(
            {
                "tool_name": "Bash",
                "cwd": cwd or self.fx.repo,
                "tool_input": {"command": command},
            }
        )
        out = io.StringIO()
        start = time.perf_counter()
        g.main([], stdin=io.StringIO(payload), stdout=out)
        took = time.perf_counter() - start
        sys.stderr.write(
            "\nperf: %-34s %8.3f s (%d bytes)" % (name, took, len(command))
        )
        self.assertLess(took, self.LIMIT, name)
        text = out.getvalue().strip()
        return (
            json.loads(text)["hookSpecificOutput"].get("permissionDecision")
            if text
            else "allow"
        )

    def test_100kb_single_word(self):
        self.assertEqual(
            self.timed("100 KB single word", "echo " + "QUJD" * 25000), "allow"
        )

    def test_100kb_word_shaped_like_a_secret_name(self):
        # The pattern that backtracked: NAME_TOKEN followed by a long word.
        self.assertEqual(
            self.timed("100 KB X_TOKEN word", "echo X_TOKEN" + "a" * 100000 + "=v"),
            "allow",
        )

    def test_1mb_command(self):
        self.assertEqual(
            self.timed("1 MB single word", "echo " + "QUJD" * 262144), "allow"
        )
        blob = json.dumps({"k%d" % i: "v" * 20 for i in range(30000)})
        self.assertEqual(
            self.timed("1 MB JSON line", "echo '%s' | jq ." % blob), "allow"
        )
        self.assertEqual(
            self.timed(
                "1 MB of words then git push",
                "echo " + "word " * 200000 + "&& git push",
            ),
            "deny",
        )

    def test_5mb_heredoc(self):
        body = "a line with token=abc, it's `git push` and $(go test)\n" * 95000
        self.assertEqual(
            self.timed("5 MB quoted heredoc", "cat <<'EOF' > f\n" + body + "EOF"),
            "allow",
        )
        self.assertEqual(
            self.timed(
                "5 MB heredoc in $(cat)",
                "gh issue comment 1 --body \"$(cat <<'EOF'\n" + body + 'EOF\n)"',
            ),
            "allow",
        )
        self.assertEqual(
            self.timed(
                "5 MB unquoted heredoc",
                "cat <<EOF > f\n" + "line $x `date` it's\n" * 300000 + "EOF",
            ),
            "allow",
        )

    def test_too_many_commands_is_refused_quickly(self):
        self.assertEqual(self.timed("500k commands", "a;" * 500000), "deny")
        self.assertEqual(
            self.timed("500k commands, outside", "a;" * 500000, cwd=self.fx.out),
            "allow",
        )

    def test_adversarial_shapes(self):
        for name, cmd in (
            ("1M open parens", "(" * 1000000),
            ("300k $( unbalanced", "$(" * 300000),
            ("1M backslashes", "\\" * 1000000),
            ("1M double quotes", '"' * 1000000),
            ("500k && ", "&&" * 500000),
        ):
            self.timed(name, cmd)

    def test_log_line_is_bounded_and_redacted(self):
        secret = "ghp_" + "A" * 36
        self.timed("secret then 1 MB", "GH_TOKEN=%s echo %s" % (secret, "x" * 1000000))
        with open(g.log_path(self.fx.home)) as fh:
            rec = json.loads(fh.readlines()[-1])
        self.assertNotIn(secret, rec["command"])
        self.assertIn("[truncated, ", rec["command"])
        self.assertLess(len(rec["command"]), 1100)


class RedactionTest(unittest.TestCase):
    def test_redacts(self):
        cases = [
            ("mysql -phunter2 db", "hunter2"),
            ("psql postgres://app:s3cr3t@db:5432/x", "s3cr3t"),
            ("redis-cli -u redis://default:r3dispass@host:6379", "r3dispass"),
            ("curl -u admin:adm1npass https://x", "adm1npass"),  # gitleaks:allow
            ("curl --user admin:adm1npass https://x", "adm1npass"),  # gitleaks:allow
            ("gh secret set FOO --body s3cretvalue", "s3cretvalue"),
            ("gh secret set FOO -b 'two words'", "two words"),
            ('gh secret set FOO --body="quoted value" -R x/y', "quoted value"),
            ("curl -H 'X-Api-Key: k3yvalue' https://x", "k3yvalue"),
            (
                "curl -H 'X-Auth-Token: t0kenvalue' https://x",  # gitleaks:allow
                "t0kenvalue",
            ),
            ("curl -H 'PRIVATE-TOKEN: glvalue123' https://x", "glvalue123"),
            (
                "curl 'https://x?key=AIzaSyA1234567890abcdefghijklmnopqrstuv'",  # gitleaks:allow
                "AIzaSyA1234567890abcdefghijklmnopqrstuv",  # gitleaks:allow
            ),
            (
                "echo ghs_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123",
                "ghs_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123",
            ),
            (
                "echo github_pat_11ABCDEFG0123456789_abcdefghijklmnop",
                "github_pat_11ABCDEFG0123456789_abcdefghijklmnop",
            ),
            ("echo xoxb-1234567890-abcdefghij", "xoxb-1234567890-abcdefghij"),
            ("echo xoxp-1234567890-abcdefghij", "xoxp-1234567890-abcdefghij"),
            (
                "echo sk-ant-api03-abcdefghijklmnopqrstuvwxyz",
                "sk-ant-api03-abcdefghijklmnopqrstuvwxyz",
            ),
            ("tool --password=hunter2", "hunter2"),
            ("tool --password hunter2", "hunter2"),
            ("curl 'https://x/?token=abc123def'", "abc123def"),
            (
                "GH_TOKEN=ghs_abcdefghijklmnopqrstuvwxyz0123 gh pr list",
                "ghs_abcdefghijklmnopqrstuvwxyz0123",
            ),
            (
                "curl -H 'Authorization: Bearer sekrit-value-123' https://x",  # gitleaks:allow
                "sekrit-value-123",
            ),
            (
                'curl -H "Authorization: token abcdefgh12345" x',  # gitleaks:allow
                "abcdefgh12345",
            ),
            ("git clone https://user:pa55word@github.com/x/y", "pa55word"),
            (
                "echo ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
                "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
            ),
            ("API_KEY=xyz789 ./run", "xyz789"),
            ("vault login --token s.abcdef", "s.abcdef"),
        ]
        for text, secret in cases:
            out = g.redact(text)
            self.assertNotIn(secret, out, text)
            self.assertIn("[REDACTED]", out, text)

    def test_leaves_ordinary_commands_alone(self):
        for text in (
            "git log --oneline",
            "go test ./...",
            "gh pr view 12",
            "git log -p 5",
            "git log -p -5",
            "patch -p1 < x.diff",
            "git apply -p2 x.patch",
            "find . -print",
            "find . -path ./x -prune",
            "sudo -u james ls",
            "mkdir -p a/b",
            "gh secret list",
            "ssh -p 2222 host",
        ):
            self.assertEqual(g.redact(text), text)


class HookHarness(unittest.TestCase):
    """Runs main() on a payload with a private HOME and policy. No tests of its own."""

    def setUp(self):
        self.fx = Fixture()
        self.policy = os.path.join(self.fx.tmp, "policy.json")
        shutil.copy(g.default_policy_path(), self.policy)
        self.env = {"AGENT_GUARD_HOME": self.fx.home, "AGENT_GUARD_POLICY": self.policy}
        self._old = {k: os.environ.get(k) for k in self.env}
        os.environ.update(self.env)

    def tearDown(self):
        for k, v in self._old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.fx.close()

    def hook(self, payload):
        out = io.StringIO()
        rc = g.main([], stdin=io.StringIO(json.dumps(payload)), stdout=out)
        self.assertEqual(rc, 0)
        text = out.getvalue().strip()
        return json.loads(text) if text else None

    def log(self):
        with open(g.log_path(self.fx.home)) as fh:
            return [json.loads(line) for line in fh]


class HookIOTest(HookHarness):
    def test_deny_uses_the_pretooluse_protocol_and_logs(self):
        out = self.hook(
            {
                "tool_name": "Bash",
                "cwd": self.fx.repo,
                "session_id": "s1",
                "tool_input": {
                    "command": "GH_TOKEN=ghs_abcdefghijklmnopqrstuvwxyz0123 git push"
                },
            }
        )
        hso = out["hookSpecificOutput"]
        self.assertEqual(hso["hookEventName"], "PreToolUse")
        self.assertEqual(hso["permissionDecision"], "deny")
        self.assertIn("//tools/git:push", hso["permissionDecisionReason"])
        rec = self.log()[-1]
        self.assertEqual(
            (rec["decision"], rec["category"], rec["scope"]),
            ("deny", "git-push", "inside"),
        )
        self.assertNotIn("ghs_", rec["command"])
        for key in ("ts", "cwd", "category", "decision", "command"):
            self.assertIn(key, rec)

    def test_allow_prints_nothing_and_logs(self):
        self.assertIsNone(
            self.hook(
                {
                    "tool_name": "Bash",
                    "cwd": self.fx.repo,
                    "tool_input": {"command": "git status"},
                }
            )
        )
        self.assertEqual(self.log()[-1]["decision"], "allow")

    def test_outside_is_allowed_and_logged(self):
        self.assertIsNone(
            self.hook(
                {
                    "tool_name": "Bash",
                    "cwd": self.fx.out,
                    "tool_input": {"command": "git push"},
                }
            )
        )
        rec = self.log()[-1]
        self.assertEqual((rec["decision"], rec["scope"]), ("allow", "outside"))

    def test_long_commands_are_truncated(self):
        self.hook(
            {
                "tool_name": "Bash",
                "cwd": self.fx.repo,
                "tool_input": {"command": "echo " + "x" * 5000},
            }
        )
        self.assertLess(len(self.log()[-1]["command"]), 1100)

    def test_warn_mode_adds_context(self):
        with open(self.policy) as fh:
            p = json.load(fh)
        p["categories"]["git-push"]["mode"] = "warn"
        with open(self.policy, "w") as fh:
            json.dump(p, fh)
        out = self.hook(
            {
                "tool_name": "Bash",
                "cwd": self.fx.repo,
                "tool_input": {"command": "git push"},
            }
        )
        self.assertNotIn("permissionDecision", out["hookSpecificOutput"])
        self.assertIn("warn mode", out["hookSpecificOutput"]["additionalContext"])
        self.assertEqual(self.log()[-1]["decision"], "warn")

    def test_terminal_panel_uses_its_own_cwd(self):
        out = self.hook(
            {
                "tool_name": "mcp__terminal__run_in_terminal",
                "cwd": self.fx.out,
                "tool_input": {"command": "git push", "cwd": self.fx.repo},
            }
        )
        self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_monitor_and_desktop_commander(self):
        for tool, field in (
            ("Monitor", "command"),
            (
                "mcp__plugin_desktop-commander_desktop-commander__start_process",
                "command",
            ),
            (
                "mcp__plugin_desktop-commander_desktop-commander__interact_with_process",
                "input",
            ),
        ):
            out = self.hook(
                {
                    "tool_name": tool,
                    "cwd": self.fx.repo,
                    "tool_input": {field: "go test ./..."},
                }
            )
            self.assertEqual(
                out["hookSpecificOutput"]["permissionDecision"], "deny", tool
            )

    def test_auto_merge_tool(self):
        url = "https://github.com/VitruvianSoftware/vitruvian-core/pull/1"
        out = self.hook(
            {
                "tool_name": "mcp__ccd_pr__set_auto_merge",
                "cwd": self.fx.out,
                "tool_input": {"enabled": True, "url": url},
            }
        )
        self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertIsNone(
            self.hook(
                {
                    "tool_name": "mcp__ccd_pr__set_auto_merge",
                    "cwd": self.fx.out,
                    "tool_input": {"enabled": False, "url": url},
                }
            )
        )
        self.assertIsNone(
            self.hook(
                {
                    "tool_name": "mcp__ccd_pr__set_auto_merge",
                    "cwd": self.fx.out,
                    "tool_input": {
                        "enabled": True,
                        "url": "https://github.com/x/other/pull/1",
                    },
                }
            )
        )

    def test_kubernetes_mcp(self):
        out = self.hook(
            {
                "tool_name": "mcp__kubernetes__kubectl_apply",
                "cwd": self.fx.repo,
                "tool_input": {"manifest": "x"},
            }
        )
        self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "deny")
        out = self.hook(
            {
                "tool_name": "mcp__kubernetes__kubectl_generic",
                "cwd": self.fx.repo,
                "tool_input": {"command": "rollout", "subCommand": "restart"},
            }
        )
        self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertIsNone(
            self.hook(
                {
                    "tool_name": "mcp__kubernetes__kubectl_generic",
                    "cwd": self.fx.repo,
                    "tool_input": {"command": "get"},
                }
            )
        )
        self.assertIsNone(
            self.hook(
                {
                    "tool_name": "mcp__kubernetes__kubectl_rollout",
                    "cwd": self.fx.repo,
                    "tool_input": {"subCommand": "status"},
                }
            )
        )

    def test_log_is_private(self):
        self.hook(
            {
                "tool_name": "Bash",
                "cwd": self.fx.repo,
                "tool_input": {"command": "git status"},
            }
        )
        path = g.log_path(self.fx.home)
        self.assertEqual(os.stat(os.path.dirname(path)).st_mode & 0o777, 0o700)
        self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
        # An existing loose directory and file are tightened.
        os.chmod(os.path.dirname(path), 0o755)
        os.chmod(path, 0o644)
        self.hook(
            {
                "tool_name": "Bash",
                "cwd": self.fx.repo,
                "tool_input": {"command": "git status"},
            }
        )
        self.assertEqual(os.stat(os.path.dirname(path)).st_mode & 0o777, 0o700)
        self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)

    def test_desktop_commander_cannot_touch_the_session_start_scripts(self):
        dc = "mcp__plugin_desktop-commander_desktop-commander__"
        for rel in ("tools/remote/setup.sh",):
            path = os.path.join(self.fx.repo, rel)
            for tool, tin in (
                ("write_file", {"path": path, "content": "exit 0"}),
                (
                    "edit_block",
                    {"file_path": path, "old_string": "a", "new_string": "b"},
                ),
                ("move_file", {"source": path, "destination": "/tmp/x"}),
                ("move_file", {"source": "/tmp/x", "destination": path}),
            ):
                out = self.hook(
                    {"tool_name": dc + tool, "cwd": self.fx.repo, "tool_input": tin}
                )
                self.assertEqual(
                    out["hookSpecificOutput"]["permissionDecision"], "deny", (tool, rel)
                )
                self.assertEqual(self.log()[-1]["category"], "guard-config")
            # A shell write through Desktop Commander's process tools too.
            out = self.hook(
                {
                    "tool_name": dc + "start_process",
                    "cwd": self.fx.repo,
                    "tool_input": {"command": "echo 'exit 0' > " + path},
                }
            )
            self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_desktop_commander_file_tools_cannot_touch_the_guard(self):
        dc = "mcp__plugin_desktop-commander_desktop-commander__"
        guard = os.path.join(self.fx.home, ".local/share/agent-guard")
        for tool, tin in (
            ("write_file", {"path": guard + "/policy.json", "content": "{}"}),
            (
                "edit_block",
                {
                    "file_path": guard + "/agent_guard.py",
                    "old_string": "a",
                    "new_string": "b",
                },
            ),
            ("move_file", {"source": "/tmp/x", "destination": guard + "/hook.py"}),
            ("move_file", {"source": guard + "/hook.py", "destination": "/tmp/x"}),
            ("create_directory", {"path": guard + "/sub"}),
            (
                "write_pdf",
                {"path": "/tmp/a.pdf", "content": "x", "outputPath": guard + "/x.pdf"},
            ),
        ):
            out = self.hook(
                {"tool_name": dc + tool, "cwd": self.fx.out, "tool_input": tin}
            )
            self.assertEqual(
                out["hookSpecificOutput"]["permissionDecision"], "deny", tool
            )
        self.assertIsNone(
            self.hook(
                {
                    "tool_name": dc + "write_file",
                    "cwd": self.fx.repo,
                    "tool_input": {
                        "path": os.path.join(self.fx.repo, "x.txt"),
                        "content": "x",
                    },
                }
            )
        )

    def test_file_tools_cannot_edit_the_installed_guard(self):
        target = os.path.join(self.fx.home, ".local/share/agent-guard/policy.json")
        out = self.hook(
            {
                "tool_name": "Write",
                "cwd": self.fx.out,
                "tool_input": {"file_path": target, "content": "{}"},
            }
        )
        self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertIsNone(
            self.hook(
                {
                    "tool_name": "Edit",
                    "cwd": self.fx.repo,
                    "tool_input": {
                        "file_path": os.path.join(
                            self.fx.repo, "tools/agent-guard/policy.json"
                        )
                    },
                }
            )
        )

    def test_file_tools_cannot_touch_the_hook_files(self):
        for tool in ("Write", "Edit", "MultiEdit"):
            for rel in (
                ".claude/settings.json",
                ".claude/settings.local.json",
                ".claude/block-queue-bypass.sh",
                ".claude/session-start.sh",
                ".agents/hooks.json",
                "tools/agent-guard/hook.sh",
                "tools/remote/setup.sh",
            ):
                for root in (self.fx.repo, self.fx.wt):
                    out = self.hook(
                        {
                            "tool_name": tool,
                            "cwd": root,
                            "tool_input": {"file_path": os.path.join(root, rel)},
                        }
                    )
                    self.assertEqual(
                        out["hookSpecificOutput"]["permissionDecision"],
                        "deny",
                        (tool, rel),
                    )
            # Relative paths count too, and the log names the file.
            out = self.hook(
                {
                    "tool_name": tool,
                    "cwd": self.fx.repo,
                    "tool_input": {"file_path": ".agents/hooks.json"},
                }
            )
            self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "deny")
            self.assertEqual(self.log()[-1]["category"], "guard-config")
        # The guard's source and policy are fine to edit: they only take
        # effect once merged, because hook.sh runs origin/main's copy.
        for rel in (
            "tools/agent-guard/agent_guard.py",
            "tools/agent-guard/policy.json",
            ".claude/notes.md",
            "tools/cloud-bootstrap/cloud-bootstrap_test.sh",
            "tools/cloud-bootstrap/README.md",
            "tools/remote/setup_test.sh",
        ):
            self.assertIsNone(
                self.hook(
                    {
                        "tool_name": "Edit",
                        "cwd": self.fx.repo,
                        "tool_input": {"file_path": os.path.join(self.fx.repo, rel)},
                    }
                ),
                rel,
            )
        # Outside a vitruvian-core checkout the same names are someone else's.
        self.assertIsNone(
            self.hook(
                {
                    "tool_name": "Write",
                    "cwd": self.fx.out,
                    "tool_input": {
                        "file_path": os.path.join(self.fx.out, ".claude/settings.json")
                    },
                }
            )
        )

    def test_log_records_which_copy_decided(self):
        os.environ["AGENT_GUARD_SOURCE"] = "origin/main:abc"
        try:
            self.hook(
                {
                    "tool_name": "Bash",
                    "cwd": self.fx.repo,
                    "tool_input": {"command": "git status"},
                }
            )
        finally:
            del os.environ["AGENT_GUARD_SOURCE"]
        self.assertEqual(self.log()[-1]["source"], "origin/main:abc")
        self.hook(
            {
                "tool_name": "Bash",
                "cwd": self.fx.repo,
                "tool_input": {"command": "git status"},
            }
        )
        self.assertEqual(self.log()[-1]["source"], "")

    def test_antigravity_format(self):
        out = self.hook(
            {
                "toolCall": {
                    "name": "run_command",
                    "args": {"CommandLine": "git stash", "Cwd": self.fx.repo},
                }
            }
        )
        self.assertEqual(out["decision"], "deny")
        self.assertIn("stash", out["reason"])
        self.assertIsNone(
            self.hook(
                {
                    "toolCall": {
                        "name": "run_command",
                        "args": {"CommandLine": "git status", "Cwd": self.fx.repo},
                    }
                }
            )
        )
        self.assertEqual(self.log()[-1]["agent"], "antigravity")

    def test_garbage_input_is_allowed(self):
        out = io.StringIO()
        self.assertEqual(g.main([], stdin=io.StringIO("not json"), stdout=out), 0)
        self.assertEqual(out.getvalue(), "")


def agy_payload(command, cwd=None, workspace=None, tool="run_command", args=None):
    """The PreToolUse payload agy 1.4.0 sends, captured live (paths faked).

    No top-level cwd and no session_id: the directory is args.Cwd and the
    session is conversationId. The hook itself runs in ~/.gemini/config.
    """
    a = {
        "CommandLine": command,
        "Cwd": cwd,
        "WaitMsBeforeAsync": 5000,
        "toolAction": "Running command",
        "toolSummary": "Run a command",
    }
    if tool != "run_command":
        a = {"toolAction": "Doing it", "toolSummary": "Do it"}
    a.update(args or {})
    if cwd is None:
        a.pop("Cwd", None)
    p = {
        "toolCall": {"name": tool, "args": a},
        "stepIdx": 3,
        "conversationId": "0f6c1d2e-3a4b-4c5d-8e9f-a0b1c2d3e4f5",
        "transcriptPath": "/fake/home/.gemini/antigravity-cli/brain/x/transcript.jsonl",
        "artifactDirectoryPath": "/fake/home/.gemini/antigravity-cli/brain/x",
        "modelName": "auto",
    }
    if workspace is not None:
        p["workspacePaths"] = workspace
    return p


BACKSTOP_CMD = "/bin/sh -c 'h=...' agent-guard-backstop /Users/j/vitruvian-core"
USER_SETTINGS: Dict[str, Any] = {
    "effortLevel": "high",
    "hooks": {
        "PreToolUse": [
            {
                "matcher": "^(Bash)$",
                "hooks": [
                    {"type": "command", "command": BACKSTOP_CMD, "onFailure": "block"}
                ],
            },
            {
                "matcher": "^(Edit)$",
                "hooks": [{"type": "command", "command": BACKSTOP_CMD}],
            },
        ],
        "Stop": [{"hooks": [{"type": "command", "command": "/h/stop.sh"}]}],
    },
}
USER_GEMINI: Dict[str, Any] = {
    "agent-guard": {
        "enabled": True,
        "PreToolUse": [
            {
                "matcher": "run_command",
                "hooks": [{"type": "command", "command": BACKSTOP_CMD}],
            }
        ],
    },
    "response-contract": {"enabled": True, "PreInvocation": []},
}


class UserFileToolTest(HookHarness):
    """The backstop's user files: other settings may change through Claude
    Code's Edit, MultiEdit and Write; agent-guard's entries and
    disableAllHooks may not; other tools may not write them at all."""

    def setUp(self):
        super().setUp()
        self.settings = os.path.join(self.fx.home, ".claude", "settings.json")
        self.gemini = os.path.join(self.fx.home, ".gemini", "config", "hooks.json")
        for path, data in ((self.settings, USER_SETTINGS), (self.gemini, USER_GEMINI)):
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as fh:
                json.dump(data, fh, indent=2)
        with open(self.settings) as fh:
            self.text = fh.read()
        with open(self.gemini) as fh:
            self.gtext = fh.read()

    def decide(self, tool, tin):
        out = self.hook({"tool_name": tool, "cwd": self.fx.out, "tool_input": tin})
        return out["hookSpecificOutput"]["permissionDecision"] if out else "allow"

    def edit(self, old, new, path=None, **kw):
        return self.decide(
            "Edit",
            dict(file_path=path or self.settings, old_string=old, new_string=new, **kw),
        )

    def test_edits_to_other_settings_are_allowed(self):
        self.assertEqual(self.edit('"effortLevel": "high"', '"effortLevel": "low"'), A)
        self.assertEqual(self.edit('"/h/stop.sh"', '"/h/stop2.sh"'), A)
        self.assertEqual(
            self.edit(
                '"response-contract": {',
                '"other": {}, "response-contract": {',
                self.gemini,
            ),
            A,
        )
        self.assertEqual(
            self.decide(
                "MultiEdit",
                {
                    "file_path": self.settings,
                    "edits": [
                        {"old_string": '"high"', "new_string": '"max"'},
                        {"old_string": "/h/stop.sh", "new_string": "/h/s.sh"},
                    ],
                },
            ),
            A,
        )

    def test_edits_that_remove_or_change_agent_guard_entries_are_refused(self):
        self.assertEqual(self.edit('"onFailure": "block"', '"onFailure": "allow"'), D)
        self.assertEqual(
            self.edit("agent-guard-backstop", "nothing", replace_all=True), D
        )
        self.assertEqual(
            self.edit('"matcher": "^(Bash)$"', '"matcher": "^(Nothing)$"'), D
        )
        self.assertEqual(
            self.edit(
                '"enabled": true,\n    "PreToolUse"',
                '"enabled": false,\n    "PreToolUse"',
                self.gemini,
            ),
            D,
        )
        self.assertEqual(
            self.decide(
                "MultiEdit",
                {
                    "file_path": self.settings,
                    "edits": [
                        {"old_string": '"high"', "new_string": '"max"'},
                        {"old_string": '"onFailure": "block"', "new_string": '"x": 1'},
                    ],
                },
            ),
            D,
        )
        # Not found in the file (so it cannot be simulated) but aimed at our entries.
        self.assertEqual(self.edit("tools/agent-guard/hook.sh gone", "x"), D)

    def test_disable_all_hooks_true_is_refused_false_is_fine(self):
        self.assertEqual(
            self.edit(
                '"effortLevel": "high"',
                '"effortLevel": "high", "disableAllHooks": true',
            ),
            D,
        )
        self.assertEqual(
            self.edit(
                '"effortLevel": "high"', '"disableAllHooks":true,"effortLevel": "high"'
            ),
            D,
        )
        self.assertEqual(
            self.edit(
                '"effortLevel": "high"',
                '"disableAllHooks": false, "effortLevel": "high"',
            ),
            A,
        )
        data = dict(USER_SETTINGS, disableAllHooks=True)
        self.assertEqual(
            self.decide(
                "Write", {"file_path": self.settings, "content": json.dumps(data)}
            ),
            D,
        )
        data = dict(USER_SETTINGS, disableAllHooks=False)
        self.assertEqual(
            self.decide(
                "Write", {"file_path": self.settings, "content": json.dumps(data)}
            ),
            A,
        )
        # Flipping an existing false to true with an edit that names only the value.
        with open(self.settings, "w") as fh:
            json.dump(dict(USER_SETTINGS, disableAllHooks=False), fh, indent=2)
        self.assertEqual(self.edit("false", "true"), D)
        self.assertEqual(self.edit("false", "false "), A)

    def test_write_must_keep_the_same_entries(self):
        kept = dict(USER_SETTINGS, effortLevel="low", model="x")
        self.assertEqual(
            self.decide(
                "Write",
                {"file_path": self.settings, "content": json.dumps(kept, indent=4)},
            ),
            A,
        )
        dropped = dict(USER_SETTINGS, hooks={"Stop": USER_SETTINGS["hooks"]["Stop"]})
        for content in (json.dumps(dropped), "{}", "{not json"):
            self.assertEqual(
                self.decide("Write", {"file_path": self.settings, "content": content}),
                D,
                content,
            )
        g2 = {k: v for k, v in USER_GEMINI.items() if k != "agent-guard"}
        self.assertEqual(
            self.decide("Write", {"file_path": self.gemini, "content": json.dumps(g2)}),
            D,
        )
        self.assertEqual(
            self.decide(
                "Write",
                {
                    "file_path": self.gemini,
                    "content": json.dumps(dict(USER_GEMINI, extra={})),
                },
            ),
            A,
        )

    def test_write_with_no_entries_to_keep_is_allowed(self):
        os.remove(self.settings)
        self.assertEqual(
            self.decide("Write", {"file_path": self.settings, "content": '{"a": 1}'}), A
        )
        self.assertEqual(
            self.decide(
                "Write",
                {"file_path": self.settings, "content": '{"disableAllHooks": true}'},
            ),
            D,
        )

    def test_other_tools_may_not_write_them(self):
        for tool, tin in (
            (g.DC + "write_file", {"path": self.settings, "content": self.text}),
            (
                g.DC + "edit_block",
                {"file_path": self.gemini, "old_string": "a", "new_string": "b"},
            ),
            (g.DC + "move_file", {"source": self.settings, "destination": "/tmp/x"}),
            (g.DC + "move_file", {"source": "/tmp/x", "destination": self.gemini}),
            (
                g.DC + "move_file",
                {"source": os.path.dirname(self.settings), "destination": "/tmp/x"},
            ),
        ):
            self.assertEqual(self.decide(tool, tin), D, tool)
        out = self.hook(
            {
                "toolCall": {
                    "name": "write_to_file",
                    "args": {"TargetFile": self.gemini, "CodeContent": "{}"},
                },
                "workspacePaths": [self.fx.out],
            }
        )
        self.assertEqual(out["decision"], "deny")

    def test_the_refusal_says_what_to_do(self):
        out = self.hook(
            {
                "tool_name": "Edit",
                "cwd": self.fx.out,
                "tool_input": {
                    "file_path": self.settings,
                    "old_string": '"onFailure": "block"',
                    "new_string": '"onFailure": "allow"',
                },
            }
        )
        msg = out["hookSpecificOutput"]["permissionDecisionReason"]
        self.assertIn("removes or changes agent-guard's entries", msg)
        self.assertIn("bazel run //tools/agent-guard:install", msg)
        self.assertEqual(self.log()[-1]["category"], "guard-config")


class AntigravityHookTest(HookHarness):
    """agy's hook format end to end: decision JSON, location, the log."""

    def tearDown(self):
        os.chdir(self._cwd)
        super().tearDown()

    def setUp(self):
        super().setUp()
        # agy runs hooks in the folder holding hooks.json, outside any repo.
        self._cwd = os.getcwd()
        self.gemini_config = os.path.join(self.fx.home, ".gemini", "config")
        os.makedirs(self.gemini_config)
        os.chdir(self.gemini_config)

    def test_real_payload_go_vet_is_denied(self):
        out = self.hook(agy_payload("go vet ./...", self.fx.repo, [self.fx.repo]))
        self.assertEqual(set(out), {"decision", "reason"})
        self.assertEqual(out["decision"], "deny")
        self.assertIn("bazel test", out["reason"])

    def test_real_payload_git_status_prints_nothing(self):
        self.assertIsNone(
            self.hook(agy_payload("git status", self.fx.repo, [self.fx.repo]))
        )
        self.assertEqual(self.log()[-1]["decision"], "allow")

    def test_log_names_the_directory_and_the_conversation(self):
        self.hook(agy_payload("go vet ./...", self.fx.repo, [self.fx.repo]))
        rec = self.log()[-1]
        self.assertEqual(rec["agent"], "antigravity")
        self.assertEqual(rec["tool"], "run_command")
        self.assertEqual(rec["cwd"], self.fx.repo)
        self.assertEqual(rec["session"], "0f6c1d2e-3a4b-4c5d-8e9f-a0b1c2d3e4f5")
        self.assertEqual((rec["scope"], rec["decision"]), ("inside", "deny"))

    def test_missing_cwd_falls_back_to_the_workspaces(self):
        # Without the fallback the guard would judge ~/.gemini/config and allow.
        out = self.hook(agy_payload("go vet ./...", None, [self.fx.repo, self.fx.out]))
        self.assertEqual(out["decision"], "deny")
        self.assertEqual(self.log()[-1]["cwd"], self.fx.repo)
        # Any workspace inside vitruvian-core puts the call inside, not just the first.
        out = self.hook(agy_payload("git push", None, ["/tmp", self.fx.repo]))
        self.assertEqual(out["decision"], "deny")
        self.assertIn("//tools/git:push", out["reason"])
        self.assertEqual(self.log()[-1]["cwd"], self.fx.repo)
        # No workspace inside: the first one decides.
        self.assertIsNone(
            self.hook(agy_payload("go vet ./...", None, [self.fx.out, "/tmp"]))
        )
        rec = self.log()[-1]
        self.assertEqual((rec["scope"], rec["cwd"]), ("outside", self.fx.out))

    def test_cwd_wins_over_workspace_paths(self):
        self.assertIsNone(
            self.hook(agy_payload("go vet ./...", self.fx.out, [self.fx.repo]))
        )
        out = self.hook(agy_payload("go vet ./...", self.fx.repo, [self.fx.out]))
        self.assertEqual(out["decision"], "deny")

    def test_no_location_at_all_is_enforced(self):
        for workspace in (None, [], [""]):
            out = self.hook(agy_payload("go vet ./...", None, workspace))
            self.assertEqual(out["decision"], "deny", workspace)
            rec = self.log()[-1]
            self.assertEqual((rec["scope"], rec["cwd"]), ("unknown", ""), workspace)
        # Read-only commands still pass, and a gh call naming another repo is
        # still out of scope.
        self.assertIsNone(self.hook(agy_payload("git status", None)))
        self.assertIsNone(self.hook(agy_payload("gh pr merge 1 -R someone/else", None)))

    def test_a_relative_cwd_is_unknown_not_the_hooks_folder(self):
        out = self.hook(agy_payload("go vet ./...", "some/dir"))
        self.assertEqual(out["decision"], "deny")
        self.assertEqual(self.log()[-1]["scope"], "unknown")

    def test_other_command_tools(self):
        cases = (
            ("shell_exec", {"Command": "go test ./..."}),
            ("shell_exec", {"command": "go test ./..."}),
            ("send_command_input", {"Input": "go test ./...", "CommandId": "c1"}),
            (
                "manage_task",
                {"Action": "send_input", "TaskId": "t1", "Input": "go test ./..."},
            ),
        )
        for tool, args in cases:
            out = self.hook(
                agy_payload(None, None, [self.fx.repo], tool=tool, args=args)
            )
            self.assertEqual(out["decision"], "deny", (tool, args))
            self.assertEqual(self.log()[-1]["category"], "go", tool)
            self.assertIsNone(
                self.hook(agy_payload(None, None, [self.fx.out], tool=tool, args=args)),
                tool,
            )
        before = len(self.log())
        self.assertIsNone(
            self.hook(
                agy_payload(
                    None,
                    None,
                    [self.fx.repo],
                    tool="manage_task",
                    args={"Action": "kill", "TaskId": "t1"},
                )
            )
        )
        self.assertEqual(len(self.log()), before)

    def test_manage_task_send_input_as_captured(self):
        # Captured live from agy 1.4.2 on 2026-10-17 (paths and ids faked): the
        # model started `cat` with run_command, then sent it a line. No Cwd, so
        # the workspace paths say where it runs.
        payload = {
            "toolCall": {
                "name": "manage_task",
                "args": {
                    "Action": "send_input",
                    "Input": "hello cat\n",
                    "TaskId": "task-3",
                    "toolAction": "Sending input to background cat process",
                    "toolSummary": "Send input to cat",
                },
            },
            "stepIdx": 2,
            "conversationId": "0f6c1d2e-3a4b-4c5d-8e9f-a0b1c2d3e4f5",
            "transcriptPath": "/fake/home/.gemini/antigravity-cli/brain/x/transcript.jsonl",
            "artifactDirectoryPath": "/fake/home/.gemini/antigravity-cli/brain/x",
            "modelName": "auto",
            "workspacePaths": [self.fx.repo],
        }
        self.assertIsNone(self.hook(payload))
        payload["toolCall"]["args"]["Input"] = "git push\n"
        out = self.hook(payload)
        self.assertEqual(out["decision"], "deny")
        self.assertIn("//tools/git:push", out["reason"])

    def test_git_commit_tool_is_a_commit(self):
        args = {"CommitMessage": "fix things"}
        out = self.hook(
            agy_payload(None, None, [self.fx.repo], tool="git_commit", args=args)
        )
        self.assertEqual(out["decision"], "deny")
        self.assertIn("//tools/git:commit", out["reason"])
        rec = self.log()[-1]
        self.assertEqual((rec["category"], rec["tool"]), ("git-commit", "git_commit"))
        self.assertIn("fix things", rec["command"])
        self.assertIsNone(
            self.hook(
                agy_payload(None, None, [self.fx.out], tool="git_commit", args=args)
            )
        )
        out = self.hook(agy_payload(None, None, None, tool="git_commit", args=args))
        self.assertEqual(out["decision"], "deny")
        self.assertEqual(self.log()[-1]["scope"], "unknown")

    def test_file_tools_cannot_touch_the_guard(self):
        guard = os.path.join(self.fx.home, ".local/share/agent-guard/policy.json")
        mine = os.path.join(self.fx.repo, "src", "main.go")
        for tool, field in (
            ("write_to_file", "TargetFile"),
            ("replace_file_content", "TargetFile"),
            ("multi_replace_file_content", "TargetFile"),
            ("notebook_edit", "NotebookPath"),
        ):
            out = self.hook(
                agy_payload(None, None, [self.fx.repo], tool=tool, args={field: guard})
            )
            self.assertEqual(out["decision"], "deny", tool)
            self.assertEqual(self.log()[-1]["category"], "guard-config", tool)
            self.assertIsNone(
                self.hook(
                    agy_payload(
                        None, None, [self.fx.repo], tool=tool, args={field: mine}
                    )
                ),
                tool,
            )

    def test_file_tools_cannot_touch_the_hook_files(self):
        for rel in (
            ".agents/hooks.json",
            ".claude/settings.json",
            "tools/agent-guard/hook.sh",
            "tools/remote/setup.sh",
        ):
            path = os.path.join(self.fx.repo, rel)
            out = self.hook(
                agy_payload(
                    None,
                    None,
                    [self.fx.repo],
                    tool="write_to_file",
                    args={"TargetFile": path},
                )
            )
            self.assertEqual(out["decision"], "deny", rel)
            self.assertIn("James's call", out["reason"])
        # And through agy's shell, wherever the command says it runs.
        out = self.hook(
            agy_payload(
                "sed -i '' s/a/b/ tools/remote/setup.sh", self.fx.repo, [self.fx.repo]
            )
        )
        self.assertEqual(out["decision"], "deny")
        self.assertIn("session start", out["reason"])

    def test_warn_mode_prints_nothing(self):
        with open(self.policy) as fh:
            p = json.load(fh)
        p["categories"]["go"]["mode"] = "warn"
        with open(self.policy, "w") as fh:
            json.dump(p, fh)
        self.assertIsNone(self.hook(agy_payload("go vet ./...", self.fx.repo)))
        self.assertEqual(self.log()[-1]["decision"], "warn")


class ParserTest(unittest.TestCase):
    def words(self, text):
        return [c.words for c in g.parse_script(text)]

    def test_quotes_and_operators(self):
        self.assertEqual(
            self.words("a 'b c' \"d $e\" && f|g; h"),
            [["a", "b c", "d $e"], ["f"], ["g"], ["h"]],
        )

    def test_redirections_are_not_arguments(self):
        cmds = g.parse_script("git log > out.txt 2>&1 < /dev/null")
        self.assertEqual(cmds[0].words, ["git", "log"])
        self.assertIn((">", "out.txt"), cmds[0].redirects)

    def test_heredoc_body_is_data(self):
        cmds = g.parse_script("cat <<'EOF' > f\ngit push\nEOF\necho done")
        self.assertEqual([c.words for c in cmds], [["cat"], ["echo", "done"]])
        self.assertEqual(cmds[0].heredocs, ["git push"])

    def test_nested_substitution(self):
        self.assertIn(["git", "push"], self.words('echo "$(echo $(git push))"'))

    def test_heredoc_inside_substitution_is_skipped(self):
        text = "echo \"$(cat <<'EOF'\nit's `git push`\nEOF\n)\" && ls"
        self.assertEqual(
            self.words(text),
            [["echo", "$(cat <<'EOF'\nit's `git push`\nEOF\n)"], ["ls"], ["cat"]],
        )

    def test_fallback_drops_heredoc_bodies(self):
        text = "cat <<'EOF'\ndon't git push\nEOF\necho \"unterminated"
        self.assertNotIn("push", g.strip_heredoc_bodies(text))
        words = [w for c in g.fallback_split(text) for w in c.words]
        self.assertNotIn("push", words)

    def test_unquoted_heredoc_runs_its_substitutions(self):
        self.assertEqual(
            g.body_substitutions("a $(git push) `go test` \\$(no) \\`no\\` $((1+2))"),
            ["git push", "go test"],
        )
        self.assertIn(["git", "push"], self.words("cat <<EOF\n$(git push)\nEOF"))
        self.assertNotIn(["git", "push"], self.words("cat <<'EOF'\n$(git push)\nEOF"))

    def test_comments(self):
        self.assertEqual(self.words("ls # git push"), [["ls"]])


@unittest.skipUnless(shutil.which("git"), "git is not on PATH")
class RealGitStateTest(unittest.TestCase):
    """probe_git_state against a real repository with a real merge conflict."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="agent-guard-git-")
        self.env = dict(
            os.environ,
            GIT_AUTHOR_NAME="t",
            GIT_AUTHOR_EMAIL="t@e",
            GIT_COMMITTER_NAME="t",
            GIT_COMMITTER_EMAIL="t@e",
            GIT_CONFIG_GLOBAL="/dev/null",
            GIT_CONFIG_NOSYSTEM="1",
        )

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def git(self, *args, check=True):
        return subprocess.run(
            ["git", "-C", self.tmp] + list(args),
            env=self.env,
            check=check,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    def test_conflict_is_seen(self):
        self.git("init", "-q", "-b", "main")
        path = os.path.join(self.tmp, "f.txt")
        with open(path, "w") as fh:
            fh.write("base\n")
        self.git("add", "f.txt")
        self.git("commit", "-qm", "base")
        self.git("checkout", "-qb", "side")
        with open(path, "w") as fh:
            fh.write("side\n")
        self.git("commit", "-qam", "side")
        self.git("checkout", "-q", "main")
        with open(path, "w") as fh:
            fh.write("main\n")
        self.git("commit", "-qam", "main")
        st = g.probe_git_state(self.tmp)
        self.assertFalse(st.in_progress)
        self.assertTrue(st.primary)
        self.git("merge", "side", check=False)
        st = g.probe_git_state(self.tmp)
        self.assertTrue(st.merge)
        self.assertEqual(st.unmerged, [os.path.realpath(path)])
        sys.stderr.write(
            "\nreal git: merge in progress detected, conflicted file %s\n"
            % st.unmerged[0]
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
