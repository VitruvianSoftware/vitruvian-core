# Remote Build Execution (RBE)

Offload your build and test actions to a remote builder backed by a shared
remote cache. GitHub Actions runners are slow and single-machine; RBE fans
actions out across a remote cluster and reuses cached results across every
machine (local laptops and CI alike).

This repo ships a **dormant** setup helper. Nothing is enabled until you run it,
and even then RBE is opt-in per build — local and offline builds keep working
exactly as before.

## Quick start

```sh
bazel run //tools/remote:setup
```

The helper prompts for a provider and an API key, writes the config, and
(optionally) provisions your GitHub Actions secret. After that, opt in per
build:

```sh
bazel build --config=remote //...
bazel test  --config=remote //...
```

Leave `--config=remote` off and everything runs locally as usual.

## Providers

- **BuildBuddy** (default) — hosted remote execution, remote cache, and a
  build-results UI. Create an account at <https://www.buildbuddy.io> and copy an
  API key from **Settings → API keys**.
- **Custom** — any Remote Execution API (REAPI) provider: NativeLink, EngFlow,
  Buildbarn, or a self-hosted cluster. You supply the `grpcs://` endpoint and the
  auth-header name; the Bazel flags are otherwise identical.

## What the helper writes

| File | Committed? | Contents |
|---|---|---|
| `tools/remote.bazelrc` | **Yes** — non-secret | The `:remote` config group: executor / cache / BES endpoints, timeouts, job count, and the default Linux exec platform. |
| `user.bazelrc` | **No** — git-ignored | Your API key as a `--remote_header` / `--bes_header`. Never commit this. |

`.bazelrc` already `try-import`s both files, so the config goes live the moment
the helper writes it. `user.bazelrc` is listed in `.gitignore`.

### Key handling

Your API key lives **only** in the git-ignored `user.bazelrc`. The helper reads
it silently — it is never echoed, logged, or written to a committed file. For
CI, the key is piped to `gh secret set` over **stdin**, so it never appears in a
process argument list or shell history. Treat the key like a password; if it
leaks, rotate it in your provider's dashboard and re-run the helper.

## CI (GitHub Actions)

Unless you pass `--no-ci`, the helper sets the `BUILDBUDDY_API_KEY` repository
secret (using your authenticated `gh` CLI) and prints a build-step snippet to add
to your Bazel job:

```yaml
    - name: Build/test with RBE
      env:
        BUILDBUDDY_API_KEY: ${{ secrets.BUILDBUDDY_API_KEY }}
      run: bazel test --config=remote --remote_header=x-buildbuddy-api-key=$BUILDBUDDY_API_KEY //...
```

The committed `tools/remote.bazelrc` supplies the endpoints; the secret header is
injected at runtime from the Actions secret, so no key is ever committed. If `gh`
is missing or unauthenticated, the helper prints the exact `gh secret set`
command for you to run yourself.

## macOS caveat

BuildBuddy's hosted executors run **Linux** actions. If this repo builds
**macOS** targets (for example Swift or Apple rules), those cannot execute on a
Linux remote — keep them local while sending the rest to RBE:

```
# in user.bazelrc or tools/remote.bazelrc
build:remote --strategy=SwiftCompile=local
```

…or scope `--config=remote` to the Linux-buildable subset of targets. The
generated `tools/remote.bazelrc` already pins `OSFamily=linux` as the default
remote exec platform.

## Non-interactive use

Everything is scriptable, which is what the verification tests use:

```sh
bazel run //tools/remote:setup -- --provider buildbuddy --no-ci
```

Flags:

| Flag | Purpose |
|---|---|
| `--provider <buildbuddy\|custom>` | Remote builder provider (prompted if omitted). |
| `--endpoint <grpcs://host>` | gRPC endpoint (custom provider). |
| `--header-name <name>` | Auth header name (custom; default `x-buildbuddy-api-key`). |
| `--key <key>` | API key — prefer the `BUILDBUDDY_API_KEY` env var or the hidden prompt over this flag. |
| `--yes` | Accepted for non-interactive callers (currently a no-op). |
| `--no-ci` | Configure local builds only; skip the CI secret and snippet. |

Re-running the helper is idempotent: it replaces the prior key header in
`user.bazelrc` and overwrites `tools/remote.bazelrc` in place, so it's also how
you rotate a key or switch providers.
