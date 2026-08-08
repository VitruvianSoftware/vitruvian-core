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
| `login <agent>` | The one agents use. Resolves ids from `agents.tsv`, finds the key, mints the token. |

```sh
export GH_TOKEN="$(bazel run //tools/agent-app -- login beacon)"   # what an agent runs
bazel run //tools/agent-app -- installations 4520098 ~/keys/beacon.pem
bazel test //tools/agent-app:agent_app_test
```

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
