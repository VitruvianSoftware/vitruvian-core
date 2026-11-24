# `//tools/claude-cli-pin:update`

Keeps the Claude Code CLI that runs the orchestrator plugin's behaviour tests
(`//apps/claude-code/plugins/vitruvian-orchestrator:plugin_test`) on the newest
release.

The pin lives in [`tools/testinfra/claude_cli.bzl`](../testinfra/claude_cli.bzl):
one version and the npm `dist.integrity` (a `sha512` checksum) of each of the
four platform packages. This tool rewrites all five together, so the version
and its checksums can never disagree.

```sh
bazel run //tools/claude-cli-pin:update             # move to npm's latest
bazel run //tools/claude-cli-pin:update -- --check  # exit 1 if a newer one exists
bazel run //tools/claude-cli-pin:update -- --version 2.1.331
```

## What it checks

- The main package answers as `@anthropic-ai/claude-code` at the version asked
  for, and lists every platform package as an optional dependency at that same
  version. A renamed or missing platform build stops the run.
- Each platform package answers with the right name and version, and a
  well-formed `sha512` integrity.
- It never moves to an older version unless you name one with `--version`.
- If the registry reports different checksums for the version already pinned,
  it stops instead of rewriting them. npm versions cannot be republished, so
  that means tampering or a broken pin, and a person should look.

Exit codes: `0` current or updated, `1` `--check` found a newer version, `2` error.
`--offline <dir>` reads recorded registry answers instead of the network, as in
[`testdata/2.1.331`](testdata/2.1.331).

## Automation

[`.github/workflows/claude-cli-pin.yaml`](../../.github/workflows/claude-cli-pin.yaml)
runs this weekly (Tuesdays `14:23 UTC`, and on `workflow_dispatch`). When the
pin changes it opens or updates `chore(testinfra): bump the Claude Code CLI to
<version>` on branch `chore/claude-cli-pin`. The required `build-test` check
then runs the plugin tests on the new CLI before it can merge.

The checksums are taken from the registry when the bump runs, and then fixed in
git. Nothing is downloaded or trusted at test time beyond that pin.
