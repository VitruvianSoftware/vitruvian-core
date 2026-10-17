# `//tools/agent-app`

Operational steps for per-agent GitHub App identities. Rationale and the
design decision live in [docs/guides/agent-github-identities.md](../../docs/guides/agent-github-identities.md);
the step-by-step runbook is [docs/guides/creating-an-agent-github-app.md](../../docs/guides/creating-an-agent-github-app.md).

| Command | What it does |
|---|---|
| `convert <code> <out.pem>` | Completes the App-manifest handshake. Prints the app id and **writes the private key** — GitHub issues it exactly once. |
| `installations <app-id> <key.pem>` | Lists the App's installations, with their ids. |
| `repos <app-id> <key.pem> <inst-id>` | Lists the repositories an installation can reach. |
| `token <app-id> <key.pem> <inst-id>` | Mints a **1-hour** installation access token. |
| `env <agent>` | **The one agents use.** Prints every export: token **and** git author identity. |
| `login <agent>` | Token only. Not sufficient on its own — see below. |
| `pr-create [--agent <agent>] [gh pr create args]` | **How agents open PRs.** Opens the PR as the agent app (default `wren`) with the `agent-fast-lane` label on at creation, so it skips the heavy PR tests; the merge queue still runs everything (#3418). Every other argument goes to `gh pr create` unchanged. The token is never printed; if it can't be minted, no PR is opened. |

`permissions.tsv` records what each App is meant to be allowed to do, and
`bazel run //tools/agent-app:permission-drift` checks GitHub against it (below).

```sh
eval "$(bazel run //tools/agent-app -- env beacon)"   # what an agent runs
bazel run //tools/agent-app -- pr-create --title "..." --body-file pr.md
bazel run //tools/agent-app -- installations 4520098 ~/keys/beacon.pem
bazel test //tools/agent-app/...
bazel run //tools/agent-app:permission-drift          # GitHub vs permissions.tsv
```

## `login` alone is not enough

`GH_TOKEN` changes who **pushes**; it does not change who **authored** the
commit. Those are separate mechanisms. A commit pushed by `beacon[bot]` with the
ambient git config still carries the machine owner's name — the PR looks right
and the history is wrong. `env` sets both, which is why it is the documented
entry point and `login` is for debugging.

`GIT_AUTHOR_*`/`GIT_COMMITTER_*` are used rather than `git config` on purpose:
they are process-scoped, so they cannot leak into a shared checkout and
mis-attribute whichever agent runs next.

## Notes that cost time to learn

- **The `code` from the manifest handshake is single-use and expires in an hour.**
  If `convert` fails, the browser step has to be redone; there is no retry.
- **The private key is returned once.** `convert` writes it under `umask 077`
  before printing anything, because a lost key means recreating the App.
- **`token` output is a credential with a 1-hour life.** That is deliberate: the
  long-lived secret is the key, so the token is minted per session rather than
  stored anywhere.
- **Pass the *installation* id, not the app id.** An App has one app id and a
  separate installation id per account it is installed on. Mixing them up yields
  a 404 that reads like a permissions problem.
- The JWT is signed with `openssl` rather than a language runtime, so this has no
  dependency beyond `curl`, `jq` and `openssl`. `iat` is backdated 60s because
  GitHub rejects a future `iat` outright — the single most common cause of an
  error that looks like a bad key.

## Permission drift check

`permissions.tsv` lists, per agent, every permission its App should have and at
what level. The check fails when GitHub says otherwise. It runs daily, and on
any change to these files reaching `main`, in
[`agent-app-permissions.yaml`](../../.github/workflows/agent-app-permissions.yaml);
a red scheduled run opens one issue.

For each App it compares what the code declares, what the org has **accepted**
(the installation), and what the App's settings **ask for**:

| Verdict | Meaning |
|---|---|
| `ok` | All three agree. |
| `PENDING` | The App asks for a change the code already declares, but the org has not accepted it yet. Someone has to click accept. |
| `DRIFT` | The code and GitHub disagree. The line names the permission and both levels. |
| `MISSING` | The App in `agents.tsv` is not installed, the installation id belongs to another App, or it is suspended. |
| `UNLISTED` | A `vitruvian-*-agent` App is installed that `agents.tsv` does not list. |
| `NOT CHECKED` | GitHub could not be read. **Never a pass**: the check exits 2. |

Reading the org's App installations needs org Administration read. Run by
hand, it uses your gh login (an org owner's is enough); an agent's own
`GH_TOKEN` gets a 403, so unset it first. In CI it uses the
`vitruviansoftware-pulumi` App's existing key (`APP_PRIVATE_KEY`), minted down
to read-only org administration.

## Changing an App's permissions

GitHub has no API for this, so it is done by hand, in this order:

1. **The App's settings.** As the App owner, open
   `https://github.com/organizations/VitruvianSoftware/settings/apps/vitruvian-<agent>-agent/permissions`,
   change the permission, and **Save changes**. GitHub asks for sudo
   (your password or passkey).
2. **Accept it on the org installation.** The installation keeps the old set
   until an org owner accepts:
   `https://github.com/organizations/VitruvianSoftware/settings/installations/<installation_id>`
   (the id is in `agents.tsv`) → **Review request** → **Accept new permissions**.
   Until then the check reports `PENDING`.
3. **Update `permissions.tsv` in the same PR** as the work that needed the
   permission, then run `bazel run //tools/agent-app:permission-drift` and
   paste its output in the PR. It should say `ok` for that App.

Removing a permission is the same three steps. If the installation still holds
it after step 1, the check says `PENDING` until it does not.
