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
| `pr-edit <pr> [gh pr edit args]` | Edits the PR as the agent: `--title`, `--body-file`, `--add-label`, and so on. |
| `pr-comment <pr> --body-file <f>` \| `--body <s>` | Comments as the agent. The body is required: without one gh waits for an editor. |
| `pr-review <pr> (--approve \| --comment \| --request-changes) [--body-file <f> \| --body <s>]` | Submits a PR review as the agent. Exactly one of `--approve`, `--comment` or `--request-changes` is required (without one gh prompts), and `--comment` / `--request-changes` require a body; `--web` is refused. Pass `--agent <reviewer>` so the review comes from a different agent than the PR author (GitHub blocks self-approval). |
| `pr-ready <pr>` | Marks a draft ready for review. |
| `pr-close <pr> [--comment <s>] [--delete-branch]` | Closes the PR. |
| `pr-enqueue <pr> [gh pr merge args]` | **How agents land PRs.** Arms auto-merge (`gh pr merge --auto`, plus `--squash` unless you chose it), so the PR joins the merge queue when its checks pass. Then asks GitHub (GraphQL) whether it took and prints which: `autoMergeRequest` (armed, waiting for checks) or `mergeQueueEntry` (in the queue). Fails if neither. Refuses a PR held with `do-not-automerge` (run `pr-unhold` first) or by a release gate's own label, `dev-deploy-red` or `beta-not-built` (the gate re-arms it itself once its condition clears), `--admin` however it is written, and `--merge`/`--rebase`, which main's ruleset does not allow, also inside short-flag clusters such as `-sm`. |
| `pr-hold <pr> [--reason <s>]` | Holds the PR, in this order: adds `do-not-automerge` (first, so no release gate re-arms it meanwhile), turns auto-merge off, then reads the PR again and takes it out of the merge queue if it is in it, even when turning auto-merge off failed. Reads the PR back and fails unless GitHub shows all three. Posts the reason as a comment after that, if given. |
| `pr-unhold <pr>` | Removes `do-not-automerge` and checks it is gone. Does **not** re-arm auto-merge: run `pr-enqueue` when the PR should land. |
| `run-rerun <run-id> [--failed] [--job <id>]` | Re-runs a workflow run. Needs Actions write. |
| `run-cancel <run-id>` | Cancels a workflow run. Needs Actions write. |
| `workflow-run <file.yaml> [-f k=v ...] [--ref main]` | Starts a workflow, **only** one listed in [`workflow-allowlist.txt`](workflow-allowlist.txt), named by its file name, from `main` (another ref runs that branch's copy of the workflow), in this repository (`--repo` is refused). Needs Actions write. |
| `issue-create --title <s> --body-file <f> \| --body <s> [gh issue create args]` | **How agents open issues.** Opens an issue in this repository as the agent. Title and body are required (without them gh prompts); `--repo` and `--web` are refused. |
| `issue-comment <issue> --body-file <f> \| --body <s>` | Comments on an issue as the agent. The body is required. |
| `issue-close <issue> [--comment <s>] [--reason completed\|"not planned"]` | Closes an issue as the agent. |
| `branch-delete <branch>...` | **How agents delete branches on GitHub.** Deletes each branch only if [`//tools/landed`](../landed)`--remote-branch` proves its work is on `main` (below). Refuses `main`, names that are not plain branch names, and a branch with an open PR (use `pr-close <n> --delete-branch`). A merge-queue branch (`gh-readonly-queue/<base>/pr-<n>-…`) is deleted once PR `<n>` is merged or closed. Reads the branch's SHA again just before deleting and keeps it if it moved. Deletes the ones that pass, keeps the rest with the reason, and fails if any was kept. There is no override. |

Every `pr-*`, `issue-*`, `run-*`, `workflow-run` and `branch-delete` command takes `--agent <agent>` as its
**first** argument (default `wren`, or `$AGENT_APP_AGENT`) and acts as that
agent's App, so an agent passes its own name. Tracing is switched off first
thing, so `bash -x` or `SHELLOPTS=xtrace` cannot print the token. The token reaches `gh` through its environment only and is never
printed. If it cannot be minted, nothing runs: no fallback to your own `gh`
login. This is how agents do these things without a raw `gh pr ...` write,
which the agent hook refuses.

**Whose identity `pr-enqueue` uses, and why.** The agent's App, not your login.
Arming auto-merge needs write access to the repo; for an App that is
`contents` and `pull_requests` write, which every agent App has. It has been
done for real: on #3421 `vitruvian-scout-agent[bot]` armed auto-merge and added
the PR to the queue, and it merged. The Apps are not bypass actors on main's
ruleset and do not need to be, because a bypass only matters for a direct
merge, which this never does.

**A hold is the label and auto-merge off, together.** Auto-merge is a setting
on the PR, not a check, so a label alone stops nothing: GitHub merges an armed
PR the moment its checks pass. `do-not-automerge` is the label the release
gates ([`release_hold`](../ci/src/release_hold/lib.rs),
[`release_beta_gate`](../ci/src/release_beta_gate/lib.rs)) treat as a person's
hold: they never remove it and never re-arm a PR that carries it. The gates' own hold labels (`dev-deploy-red`, `beta-not-built`) are copied
into `src/agent_app/mod.rs` so `pr-enqueue` can refuse them too. Each name is
pinned twice: by this tool's tests and by the gate's own
(`//tools/ci:release_hold_test`, `//tools/ci:release_beta_gate_test`), so a
rename on either side fails a test.

**Tests run the real `--jq` filters.** The fake `gh` in `agent-app_test.sh`
answers with responses saved from GitHub ([`testdata/`](testdata/README.md))
passed through the script's own filters by a real `jq`, so a typo in a
filter fails CI. `WORKFLOW_ALLOWLIST` and `AGENT_PERMISSIONS` exist for that
test and are ignored outside `bazel test`.

**What `branch-delete` counts as landed.** `main` is squash-only, so a merged
branch's SHAs are never on it; `landed --remote-branch` fetches the branch and
passes it on any one of four proofs: its tip is on `main`; merging it into
`main` would change nothing; its PR merged and the tip is the PR's head; or its
PR merged and every commit after the head is empty, a merge with no hand-made
resolution, or a patch `main` already has. Everything else is kept, including
work that looks abandoned: deleting that is a person's call, on GitHub. The
gate is the `//tools/landed` binary built with agent-app, found beside it (in
`bazel-bin`) or in its runfiles, never in the source checkout, which has no
copy. `AGENT_APP_LANDED` replaces it only under `bazel test`, so an agent
cannot name a gate of its own.

**Actions write is wren's only** ([`permissions.tsv`](permissions.tsv)). The
three run commands check that file first and refuse for any other agent,
naming wren, instead of letting GitHub answer with a bare 403.

`permissions.tsv` records what each App is meant to be allowed to do, and
`bazel run //tools/agent-app:permission-drift` checks GitHub against it (below).

```sh
eval "$(bazel run //tools/agent-app -- env beacon)"   # what an agent runs
bazel run //tools/agent-app -- pr-create --title "..." --body-file pr.md
bazel run //tools/agent-app -- pr-enqueue 123          # arm auto-merge, confirm on GitHub
bazel run //tools/agent-app -- run-rerun 18000000000 --failed
bazel run //tools/agent-app -- workflow-run catalog-bump.yaml
bazel run //tools/agent-app -- branch-delete --agent atlas old/branch other/branch
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
