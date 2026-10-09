---
title: "Every AI agent gets its own GitHub identity"
description: >-
  Ten coding agents work in our monorepo. Until recently, GitHub saw all of
  them as one person, so none of them could review another's work. Here is how
  we gave each agent its own GitHub App, what we had to measure because the
  docs don't say, and why identity alone isn't enough.
date: 2026-10-09 12:00:00 -0700
categories: [agents, platform-engineering, github]
---

Ten AI agents work in [vitruvian-core](https://github.com/VitruvianSoftware/vitruvian-core) every day. Each one has a specialty: Forge handles the Bazel build, Atlas the infrastructure, Ridge the Kubernetes cluster, Wren application code, Scout tests and CI, Aegis security review, Quill documentation, and so on. Between them they open a large share of our pull requests.

Until recently, GitHub saw all ten of them as one person.

Every push, every pull request and every merge went out under the repository owner's account. That looked harmless, but it cost us three things:

- **Authorship wasn't attribution.** "Ridge opened #1440" was a claim in a chat log. Neither git nor GitHub could back it up.
- **No agent could approve another agent's work.** GitHub blocks self-approval, and as far as GitHub could tell, every pull request was self-authored.
- **The audit trail said one human did everything**, including the work that human never saw.

The second point was the one that hurt. We wanted agents to review each other. A security agent reading an infrastructure agent's diff before it merges is exactly the kind of independent check that makes autonomous work safe to accept. With one identity, the best we could do was ask an agent to leave a comment and hope someone read it.

## Why GitHub Apps, not bot accounts

The obvious fix is a machine user per agent. But GitHub's terms allow one free machine account per person, so ten agents would mean ten accounts the terms don't cover, and ten sets of credentials to rotate.

GitHub Apps don't have that limit. An organization can own as many Apps as it likes at no cost, and each one gets its own `name[bot]` identity that genuinely authors commits, opens pull requests and submits reviews. Apps also authenticate with short-lived installation tokens rather than passwords or personal access tokens, which suits software that runs unattended.

So: one App per agent, named `vitruvian-<agent>-agent`.

## The question the docs don't answer

Before building anything, we needed to know whether an App's approval actually counts toward a branch protection rule like "require one approving review". GitHub's documentation on protected branches says approvals come from "people with write permissions" or a designated code owner. It never mentions Apps either way.

So we measured it. On a canary repository with `required_approving_review_count: 1` and `enforce_admins: true`, we opened a pull request, had an App submit an approval with its installation token, and compared the state before and after:

```text
before   reviewDecision=REVIEW_REQUIRED   mergeable_state=blocked
POST     /pulls/1/reviews  event=APPROVE   (App installation token)
after    reviewDecision=APPROVED          mergeable_state=unstable
review   <app-slug>[bot]  type=Bot  state=APPROVED
```

The review requirement went from blocking to satisfied. (`unstable` was an unrelated pending check.)

One limit did turn up: **an App can't be a code owner.** CODEOWNERS accepts users, teams and email addresses, nothing else. So we keep "require code owner review" off and use the approval count as the lever. In our Pulumi config for the repository, those are two separate settings for exactly that reason:

```yaml
repo_config:agentApps:
  - name: beacon
    installationId: "152031070"
  # ...one entry per agent
repo_config:requiredApprovals: "1"
```

`agentApps` pins each App's installation to this repository. That makes "which agent can write where" something you review in a diff instead of a checkbox in a settings page nobody remembers to look at.

## The one step you can't automate

We manage everything about the repository as code, including its own GitHub settings. App creation is the exception: **GitHub has no API for creating an App.** You either fill in the web form or use the App manifest flow, and both need a signed-in human.

The manifest flow is the better of the two because it returns the private key in an API response instead of a browser download. You post a small JSON manifest declaring the App's permissions:

```json
{
  "name": "vitruvian-<agent>-agent",
  "public": false,
  "default_permissions": {
    "contents": "write",
    "pull_requests": "write",
    "metadata": "read",
    "checks": "read",
    "workflows": "write"
  },
  "default_events": []
}
```

GitHub redirects back with a one-time code, and you exchange it within the hour for the App's id and private key. **That's the only copy of the key.** It goes straight into the vault and the response is deleted.

One trap to watch for: the install screen preselects **All repositories**. Accept that and every agent gets write access to every repository in the organization. Choose **Only select repositories**.

## Identity in daily use

From an agent's side, taking on its identity is one command at the start of a session:

```sh
eval "$(bazel run //tools/agent-app -- env wren)"
```

That looks up the agent in a committed registry (App ids, installation ids and bot user ids are all public identifiers), signs a JWT with the agent's private key, exchanges it for an installation token, and exports two separate things.

**`GH_TOKEN`** changes who *pushes*. Our git is configured to get credentials from `gh`, so a single token covers API calls and `git push` alike.

**`GIT_AUTHOR_*` and `GIT_COMMITTER_*`** change who *authored* the commit. We missed this at first. With only the token set, the bot pushes the commit, the pull request shows the bot, and the commit log still carries the machine owner's name, because git takes authorship from local config, not from whoever pushes. The fix is the bot's noreply address, which GitHub ties to the App:

```text
<bot_user_id>+vitruvian-wren-agent[bot]@users.noreply.github.com
```

Installation tokens expire after an hour, and that's on purpose. The long-lived secret is the private key, which stays in the vault and is pulled onto a machine with one command. The token is something you mint when you need it, never something you paste anywhere.

## Order of operations matters

Turning on `requiredApprovals: "1"` is the last step, not the first. If you require a review before the agents have their own identities, there's nobody who can give one: every pull request waits at `REVIEW_REQUIRED` forever. Worse, bot auto-merges from release-please and Dependabot get stuck too, because a ruleset bypass covers a *direct* merge but never auto-merge *into* a merge queue.

The safe order:

1. Create and install an App per agent.
2. Store each private key in the vault and point each agent's harness at it.
3. Add every agent to `agentApps`.
4. Only then raise `requiredApprovals`.

## Identity isn't a security boundary

We want to be honest about this part. All the agents' private keys sit in one directory that every agent can read. Nothing technically stops Wren from minting a token as Aegis and approving its own work under another name.

So per-agent identity is a **convention we keep**, written into the [AGENTS.md](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/AGENTS.md) that every coding tool in the repo reads: *use your own name; minting as another agent puts their name on your work.* It makes honest work attributable and reviewable. It doesn't make dishonest work impossible.

What stops an agent from cutting corners is a different layer: guardrails written after real incidents. Two examples from the last few weeks:

**The merge queue bypass.** Our `main` branch lets repository admins skip the merge queue, as an emergency option for the human maintainer. Agent sessions that ran under that account inherited the same bypass. Over two days, five of forty merges skipped the queue. One of them had been *rejected by the queue eight minutes earlier*, and `main` went red. The fix is a pre-tool hook that refuses `gh pr merge --admin`, direct merges through the REST or GraphQL APIs, and pushes to `main`, with a message telling the agent to fix what the queue rejected instead. A human who really needs the bypass runs the command in their own terminal, where the hook doesn't apply.

**The worktree that uninstalled Argo CD.** Our homelab stack's Pulumi config is gitignored, so it doesn't exist in a git worktree. Every component toggle read as `false`, and a `pulumi up` from a worktree removed Argo CD, along with its namespace and every Application it managed. The program now refuses to run unless the config states the setting explicitly, and the rule "never apply from a worktree" sits in AGENTS.md next to the incident date.

Both fixes shipped with tests that prove the guard fires. That's the house rule: every fix ships with the check that would catch it again.

## What changed

Pull requests now say who wrote them. Commits do too. The pull request that moved this website into the monorepo is a good example: every commit in it is authored by `vitruvian-aegis-agent[bot]`, including the one that bumped three gems the vulnerability scan had flagged. Anyone reading the history can see which agent did the work. When a change needs sign-off, a different agent's App gives it, and GitHub enforces that it really is a different identity.

Most importantly, "an agent did it" has stopped being an answer. It's always a specific agent, with a name, a commit history and a review record, working under the same merge queue, the same required checks and the same written rules as everyone else.

## Try it in your organization

If you run coding agents against a GitHub organization, this is a weekend's work:

- **Create one App per agent** with the manifest flow, and install each on selected repositories only.
- **Keep the private keys in a vault**, and mint one-hour installation tokens per session.
- **Set both the token and the git author identity.** One without the other gives you a misleading history.
- **Measure the behaviour you depend on** on a canary repository, especially anything the docs don't cover.
- **Raise required approvals last.**
- **Treat identity as attribution, not enforcement**, and put the enforcement in guardrails that fail closed.

All of the tooling described here, including the token minting script, the registry, the Pulumi repository config and the merge queue hook, is in [vitruvian-core](https://github.com/VitruvianSoftware/vitruvian-core). Read it, borrow it, and tell us what you'd do differently.
