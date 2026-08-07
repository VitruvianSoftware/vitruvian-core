# SOP: creating an agent's GitHub App identity

The exact steps used to create the nine agent Apps in `VitruvianSoftware`, in
order, including the two that trip people up. Roughly five minutes per agent.

Why per-agent Apps at all, and the evidence that an App's approval counts:
[agent-github-identities.md](agent-github-identities.md).

## Before you start

- You must be **signed in to GitHub as an organization owner** in the browser.
- **Sudo mode expires.** Creating an App and changing an installation are both
  sudo-protected. GitHub will interrupt with *"Confirm access"* and ask for a
  passkey. It lasts a few hours after you clear it, so clear it **once** at the
  start and do all the agents in one sitting. Hitting this halfway through is the
  most likely way to lose your place.
- `curl`, `jq` and `openssl` for the CLI half. No language runtime is needed.

## 1. Create the App (browser)

Do **not** use the "New GitHub App" form. Use the **manifest flow** — the form
makes you set fifteen fields by hand and hands the private key back through a
download button, while the manifest sets them declaratively and returns the key
to a command. From any page on `github.com`, in the JS console:

```js
const manifest = {
  name: "vitruvian-<agent>-agent",
  url: "https://github.com/VitruvianSoftware",
  redirect_url: "https://github.com/settings/apps",
  public: false,
  default_permissions: {
    contents: "write",
    pull_requests: "write",
    metadata: "read",
    checks: "read",
    workflows: "write",
  },
  default_events: [],
};
const f = document.createElement("form");
f.method = "post";
f.action =
  "https://github.com/organizations/VitruvianSoftware/settings/apps/new?state=<agent>";
const i = document.createElement("input");
i.type = "hidden";
i.name = "manifest";
i.value = JSON.stringify(manifest);
f.appendChild(i);
document.body.appendChild(f);
f.submit();
```

That lands on a confirmation page with the name pre-filled. Click
**Create GitHub App for VitruvianSoftware**.

You are redirected to `redirect_url` with `?code=…` in the address bar. **Copy
that code.**

> The button is not reachable from `document.querySelectorAll('button')` — it
> lives outside the queryable DOM, so scripted clicks that work elsewhere on
> GitHub silently find nothing here. Click it, or drive it through an
> accessibility-tree click.

## 2. Convert the code into an App + private key (CLI)

```sh
bazel run //tools/agent-app -- convert <CODE> ~/keys/<agent>.pem
```

Prints `app_id`, `slug`, `owner`, and writes the key at mode 600.

> **The code is single-use and expires an hour after step 1**, and **the private
> key is issued exactly once**. If this command fails, redo step 1. If you lose
> the key, the App has to be recreated.

## 3. Install it on the organization (browser)

```
https://github.com/apps/vitruvian-<agent>-agent/installations/new/permissions?target_id=228271878&target_type=Organization
```

(`228271878` is the `VitruvianSoftware` org id.)

> **Do not accept the default.** The page preselects **All repositories**, which
> grants the App write access to every repo in the org. Choose **Only select
> repositories** and pick `vitruvian-core`.

Click **Install**. You land on
`…/settings/installations/<INSTALLATION_ID>` — **the installation id is in that
URL**, which saves an API round-trip.

## 4. Verify — do not trust the redirect (CLI)

```sh
bazel run //tools/agent-app -- installations <APP_ID> ~/keys/<agent>.pem
bazel run //tools/agent-app -- repos <APP_ID> ~/keys/<agent>.pem <INSTALLATION_ID>
```

`repos` must list `VitruvianSoftware/vitruvian-core` and nothing you did not
intend. This is the step that catches an accidental "All repositories".

## 5. Record it in code

Add the agent to `agentApps` in
`infrastructure/pulumi/platform/repo_config/Pulumi.dev.yaml`:

```yaml
vitruvian-core-repo-config:agentApps:
  - name: <agent>
    installationId: "<INSTALLATION_ID>"
```

From here the repository selection is managed by Pulumi, so a change to which
repos an agent can reach is a reviewable diff rather than a checkbox.

## 6. Only after every agent exists

Set `requiredApprovals: "1"`. Doing it earlier re-creates a known wedge: with one
identity there is no second reviewer, so every PR sits at `REVIEW_REQUIRED`
forever and bot auto-merge (release-please, Dependabot) stalls — a ruleset bypass
applies to a *direct* merge, never to auto-merge *into* the merge queue.

`requireCodeOwnerReview` stays **off**: an App cannot be listed in CODEOWNERS.

## Deleting a repository an App is installed on

GitHub does not permit an installation with **zero** repositories. If an App is
installed on exactly one repo and you delete that repo, the installation can go
with it. Add the new repository **before** removing the old one.

## The nine Apps

| Agent | App | app id | installation id |
|---|---|---|---|
| Beacon | `vitruvian-beacon-agent` | 4520098 | 152031070 |
| Atlas | `vitruvian-atlas-agent` | 4521079 | 152054030 |
| Ridge | `vitruvian-ridge-agent` | 4521089 | 152054236 |
| Wren | `vitruvian-wren-agent` | 4521094 | 152054411 |
| Scout | `vitruvian-scout-agent` | 4521103 | 152054588 |
| Quill | `vitruvian-quill-agent` | 4521110 | 152054783 |
| Compass | `vitruvian-compass-agent` | 4521117 | 152054955 |
| Pace | `vitruvian-pace-agent` | 4521124 | 152055117 |
| Aegis | `vitruvian-aegis-agent` | 4521137 | 152055295 |

App ids and installation ids are not secrets — the private keys are, and they are
not in this repository.
