# Agent GitHub identities

Every agent — Beacon, Atlas, Ridge, Wren, Scout, Quill, Compass, Pace, Aegis —
pushes, opens PRs and merges as the single account `ipv1337`. That costs three
things:

- **PR authorship is not attribution.** "Ridge opened #1440" is a claim in a chat
  message, not something git or GitHub can corroborate.
- **No agent can approve another's work.** GitHub blocks self-approval, and every
  PR is self-authored from GitHub's point of view.
- **The audit trail says one human did all of it.**

The fix is one **GitHub App per agent**. Apps are not user accounts, so the
"one free machine account per person" limit in GitHub's ToS does not apply, and
an organization can own unlimited Apps at no cost. Each App gets its own
`<name>[bot]` identity that authors commits and PRs for real.

## What is settled, and how

**An App's approval satisfies `required_approving_review_count`.** This is not
in GitHub's documentation — the protected-branches page says approvals come from
*"people with write permissions… or a designated code owner"* and never mentions
Apps either way. It was measured on a canary PR with
`required_approving_review_count: 1` and `enforce_admins: true`:

```
before   reviewDecision=REVIEW_REQUIRED   mergeable_state=blocked
POST     /pulls/1/reviews  event=APPROVE   (App installation token)
after    reviewDecision=APPROVED          mergeable_state=unstable
review   <app-slug>[bot]  type=Bot  state=APPROVED
```

`unstable` was an unrelated pending check. The review requirement itself went
from blocking to satisfied.

**An App cannot be a code owner.** GitHub's CODEOWNERS documentation enumerates
users, teams and email addresses. So `requireCodeOwnerReview` stays **off** and
`requiredApprovals` is the lever — the two are separate config keys in
`repo_config` precisely because of this.

## The one manual step

**GitHub has no API to create a GitHub App.** Creation is the web form or the
App-manifest flow, both of which need a signed-in human, and **the private key is
returned exactly once**, at creation. So per agent there is one irreducible
manual step. Everything after it is code.

The manifest flow is the cheaper of the two, because it returns the private key
programmatically instead of via a download button. Submit a form to
`https://github.com/organizations/<ORG>/settings/apps/new?state=<state>` with a
`manifest` field:

```json
{
  "name": "vitruvian-<agent>-agent",
  "url": "https://github.com/<ORG>",
  "redirect_url": "https://github.com/settings/apps",
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

Click **Create GitHub App for &lt;ORG&gt;**. GitHub redirects to `redirect_url`
with `?code=…`; exchange it **once, within an hour**:

```sh
curl -s -X POST "https://api.github.com/app-manifests/<CODE>/conversions" \
  -H "Accept: application/vnd.github+json" > app.json
```

That response contains `id` (the app id) and `pem` (the private key). Store the
key as a secret immediately and delete the response — it is the only copy.

**When installing, do not accept the default.** The install screen preselects
**All repositories**, which grants the App write access to every repo in the org
including `vitruvian-core`. Choose **Only select repositories**.

## What is in code

`infrastructure/pulumi/platform/repo_config`:

- **`agentApps`** — a list of `{name, installationId}`. Each entry pins that
  App's installation to this repository, so "which agent can write where" is
  reviewable in a diff rather than a checkbox in a web form. Use the
  **installation** id (from `/orgs/<ORG>/installations`), not the app id; passing
  the app id yields a 404 that reads like a permissions problem.
- **`requiredApprovals`** — the approval count. Independent of
  `requireCodeOwnerReview`, since an App can satisfy one and not the other.

```yaml
repo_config:agentApps:
  - name: beacon
    installationId: "152031070"
repo_config:requiredApprovals: "1"
```

Both default to zero/empty, which changes nothing.

## Order of operations

Raising `requiredApprovals` **before** the agents author PRs under their own Apps
re-creates a known failure: with one identity there is no second reviewer, so
every PR sits at `REVIEW_REQUIRED` forever and bot auto-merge
(release-please, Dependabot) wedges — a ruleset bypass applies to a *direct*
merge, never to auto-merge *into* the merge queue.

1. Create and install an App per agent.
2. Store each private key as a secret; point each agent's harness at it so `gh`
   runs on a minted installation token instead of a human PAT.
3. Add every agent to `agentApps`.
4. Only then set `requiredApprovals: "1"`.
