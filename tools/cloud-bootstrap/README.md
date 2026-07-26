# cloud-bootstrap

Turn a Claude Code **cloud** sandbox into a working vitruvian-core dev machine:
the repo's CLI tooling, plus exactly the credentials the session's **profile** is
allowed to hold.

```sh
bazel run //tools/cloud-bootstrap            # install + authenticate (what the hook runs)
bazel run //tools/cloud-bootstrap:whoami     # what does this session actually have?
bazel run //tools/cloud-bootstrap:profiles   # list the declared profiles
```

It normally runs by itself, as the first `SessionStart` hook in
`.claude/settings.json`, ahead of `tailscale-up.sh` and `kube-setup.sh`.

## The problem

A cloud session boots a bare Ubuntu box. It has `git`, `go`, `node` and `docker`
— and no `bazel`, no `gh`, no `gcloud`, no `pulumi`, no `direnv`. It also has no
credentials for any of them, and no human at a browser to run `gcloud auth login`
or `pulumi login`. The agent drives these tools, so every credential has to be a
**token a process can present unattended**.

## Two knobs on the cloud environment

| variable | what it is |
| --- | --- |
| `VITRUVIAN_PROFILE` | which profile(s) this environment is. Selects one or more rows of [`profiles.tsv`](profiles.tsv). |
| `VITRUVIAN_CLOUD_KEY` | that profile's GCP service-account key (raw JSON or base64). The **only** credential on the environment. |

Per-profile keys (`VITRUVIAN_CLOUD_KEY_INFRA`, …) are honored first, so one
environment can hold several and `VITRUVIAN_PROFILE` switches identity with it.

## Combining profiles

`VITRUVIAN_PROFILE=core,homelab` unions their tools and their secrets.

This does **not** merge privileges into one identity. Each profile keeps its own
service account and reads only its own secrets — every `gcloud secrets versions
access` carries that profile's `--account` and `--project` — so the boundary
above still holds; the session simply holds two identities rather than one
broader one. That is why combining is safe, and it is the first thing the test
pins.

Consequences worth knowing:

- **Each profile needs its own key**, in `VITRUVIAN_CLOUD_KEY_<PROFILE>`. The
  shared `VITRUVIAN_CLOUD_KEY` can only satisfy one of them; identity pinning
  refuses the rest rather than authenticating them as the wrong account.
- **The first listed profile with an identity is the primary** — the one that
  becomes ambient for `pulumi`, `gsutil` and a bare `gcloud`
  (`GOOGLE_APPLICATION_CREDENTIALS`, `CLOUDSDK_CORE_PROJECT`). Order the list
  accordingly: `infra,homelab` if you want to run Pulumi. `:whoami` marks it
  `[primary]`.
- **Two profiles mapping the same env var to different secrets is refused.**
  Which credential the session ends up holding must not depend on manifest row
  order. Identical mappings (every profile wants the same `GH_TOKEN`) are a
  harmless overlap and resolve once.
- A repeated name is deduped; **one unknown name refuses the whole list**, so
  there is no partial bootstrap.

## The profile is the blast-radius boundary

`profiles.tsv` — not this script, and not the agent — decides which CLIs get
installed and which secrets a session may hold:

| profile | gets | for |
| --- | --- | --- |
| `core` | bazel, direnv, gh + a GitHub token and a BuildBuddy key | build, test, review, open PRs |
| `infra` | core + gcloud, pulumi + a Pulumi token | Pulumi/GCP infrastructure work |
| `homelab` | core + kubectl, tailscale + the Tailscale auth key and cluster token | tailnet, k3s, node SSH |
| `readonly` | bazel, direnv. **Nothing else.** | untrusted input, third-party code review, a spike |

A `core` session cannot obtain a Pulumi token even if one exists: its row does
not name it, and its service account has no IAM to read it. **Add capability by
adding a row, never by widening one.**

## Why one credential and not one per tool

The obvious approach is a token per tool pasted into the environment's variables.
That does not scale and does not rotate — N long-lived secrets, each rotated by
hand, in a box whose own UI warns *"these are visible to anyone using this
environment"*.

So there is exactly one, and its only permission is
`secretmanager.secretAccessor` on that profile's secrets. Everything else is
fetched from Secret Manager at session start — the same mechanism
[`//tools/saas-cli`](../saas-cli) already uses for Neon and Upstash, and
[`//tools/gcp-secrets`](../gcp-secrets) seeds. That buys:

- **one thing to rotate**, per profile, in one place;
- **downstream secrets rotate with no environment edit at all** — change the
  Secret Manager value and the next session picks it up;
- **the credential on the environment is worthless alone.** It cannot deploy,
  read app data, or touch a cluster. It reads a named list of secrets. Full stop.

### Identity pinning

The key's `client_email` **must** equal the `sa_account` its profile declares.
Pasting the `infra` key into an environment labelled `core` is refused, loudly,
and **fails closed** — no secret is read with a key we just declined to trust.
Same reflex as `infrastructure/gcp-identities.tsv`: never trust the ambient
identity, always assert the declared one.

### Placeholders are not credentials

The sandbox pre-sets `GH_TOKEN`, `GITHUB_TOKEN`, `AWS_ACCESS_KEY_ID` and
`CLOUDSDK_AUTH_ACCESS_TOKEN` to short dummy strings. An env var already set on
the environment normally **wins** (that is the no-GCP escape hatch, and how the
existing `TS_AUTHKEY` / `LAB_SA_TOKEN` wiring keeps working) — but a value too
short to be a credential loses to the profile's secret instead. Otherwise the
real token is never fetched and every call 401s against a credential the report
called fine.

`CLOUDSDK_AUTH_ACCESS_TOKEN` gets cleared outright: `tools/pulumi/pulumi_cmd.sh`
treats a non-empty one as *"ambient credentials present"* and deliberately skips
its `gcp-identities.tsv` pin, so a leftover dummy would send every
`bazel run //…:preview` at GCP with a token that cannot work.

### Why not keyless

CI is keyless — GitHub Actions mints an OIDC token and Workload Identity
Federation exchanges it, so no key exists. A Claude cloud sandbox exposes no OIDC
issuer to federate against, so a key is the floor today. `profiles.tsv` is the
only thing that changes if that stops being true: swap `sa_account` for a WIF
provider and no caller moves.

## Setting up a profile

1. **Create the service account** and grant it `secretmanager.secretAccessor` on
   *only* that profile's secrets. Declare it in the app's Pulumi stack — the IAM
   half of a secret is code (principles §2.3).
2. **Seed the secret values** (the half that cannot be committed, §2.4):
   ```sh
   bazel run //tools/gcp-secrets:seed -- tabula/infra/build claude-cloud-core-github-token
   ```
3. **Add the row** to `profiles.tsv`.
4. **Set the cloud environment's variables** to `VITRUVIAN_PROFILE=<name>` (or a
   comma-separated list) and `VITRUVIAN_CLOUD_KEY=<the key>` — one
   `VITRUVIAN_CLOUD_KEY_<PROFILE>` per profile if you combine several. The key is
   multiline JSON and the box is `.env` format, so base64 it onto one line:
   `base64 -w0 key.json`.
5. **Verify** from a session: `bazel run //tools/cloud-bootstrap:whoami`.

## What it installs, and what it deliberately does not

Only what has to exist **before `bazel run` works**: `bazelisk` (as both
`bazelisk` and `bazel`), `direnv`, `gh`, `gcloud`, `pulumi`, `kubectl`, and
`tailscale` + `tailscaled`.

Tailscale is installed here rather than from the cloud environment's *Setup
script* so it is a profile decision like everything else — only `homelab` pays
for it, instead of every environment installing it unconditionally. It comes
from the pinned static tarball rather than `curl https://tailscale.com/install.sh
| sh`, which detects the distro and shells out to apt: same artifact, pinned, and
it does not drag in a repo and keyring the sandbox does not need. Both binaries
install together — `tailscale-up.sh` runs the daemon *and* the client, so a
half-install is worse than none. That hook still starts the daemon each session,
because the environment cache snapshots files, not running processes.

Everything else is already the repo's job and is not duplicated here —
`//tools:bazel_env` exports buildifier, gazelle, aspect, addlicense, format and
the Go/Node/Python/JVM/Ruby toolchains onto `$PATH` via `.envrc`, and bazelisk
takes its version from `.bazelversion`. `direnv` is installed (and hooked into
`~/.bashrc`) precisely so that tree activates.

`gh`, `gcloud` and `pulumi` are pinned in the script and overridable per session
(`GH_VERSION`, `GCLOUD_VERSION`, `PULUMI_VERSION`) — the Squawk/neonctl reasoning:
a surprise major must not land mid-incident. `bazelisk` and `direnv` come from
their version-less `latest` assets on purpose: one is a launcher that honors
`.bazelversion` (the pin that actually determines the build) and the other only
execs `.envrc`, so pinning them would add rot for no reproducibility gain.
`.devcontainer/Dockerfile` takes bazelisk the same way.

## Where things land

Nothing is written inside the workspace — a stray `git add -A` must not be able
to stage a credential, and the secret-scan gate would (rightly) fail the push.

```
~/.config/vitruvian-core/cloud/sa-key-<profile>.json   0600   the decoded key, one per profile
~/.config/vitruvian-core/cloud/session.env             0600   the resolved credentials
~/.bashrc                                                     sources the above (marker-delimited)
```

One key file per profile, because several identities can be active at once and
the primary's path is what `GOOGLE_APPLICATION_CREDENTIALS` points at for the
whole session.

`GOOGLE_APPLICATION_CREDENTIALS` points at the key file rather than exporting a
minted access token: a token expires in an hour and a Claude session outlives
that, whereas the key file lets every Google client refresh on its own — and it
is exactly the "ambient credentials present" case `pulumi_cmd.sh` already
documents, so `bazel run //…:preview` works unchanged.

`~/.bashrc` is the carrier because every Bash tool call starts a fresh shell from
the profile; `$CLAUDE_ENV_FILE` is also written when the harness provides one.
The sibling hooks (`tailscale-up.sh`, `kube-setup.sh`) source `session.env`
directly, since hooks are separate processes and would not otherwise see a
`TS_AUTHKEY` or `LAB_SA_TOKEN` fetched from Secret Manager.

## Failure behavior

`up` / `install` / `auth` are **best-effort and always exit 0** — a bootstrap
hiccup must never block the Claude session (same contract as `tailscale-up.sh`
and `kube-setup.sh`) — and say loudly on stderr what went wrong.

`whoami` is the opposite: it exits **non-zero** when the profile is not fully
satisfied, so it works as a gate. It never prints a secret value; a credential is
reported by name and byte length, which is enough to tell a real token from a
truncated paste.

An unset or unknown `VITRUVIAN_PROFILE` bootstraps **nothing** and lists the
valid names — as does a list containing one bad name. There is deliberately no
default: a session's capability is a choice, not a fallback.

## Tests

`bazel test //tools/cloud-bootstrap:cloud_bootstrap_test` — hermetic, driving the
real script's `auth` path against a fake `gcloud` that records argv. It pins the
properties whose failure would be a privilege escalation or a leak: no implicit
privileged default; a mismatched key refused **and failing closed**; the key
travelling as a `--key-file` path and never as argv bytes (`ps` is world
readable); every secret read account+project pinned; values absent from all
output and landing only in a 0600 file outside the workspace; gcloud's
exit-0-with-`ERROR:` auth failure still fatal; a real ambient value winning and a
placeholder losing; and the ambient-token scrub that keeps the Pulumi wrapper's
identity pin working.

For combined profiles it additionally pins the property that makes combining
safe: each profile's secret is read as **its own** service account, with its own
project, and one profile's SA is never used to read another's secret. Plus
primary selection by list order, conflicting-mapping refusal, dedup, and
all-or-nothing on an unknown name.

The installers are not covered — they are network downloads whose only
interesting property is whether `curl` worked.
