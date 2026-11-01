# `//tools/secret-scan` — the CI secret scan, locally

Looks for secrets with the same gitleaks version and the same rules
(`.gitleaks.toml`) as the required `secret-scan` check.

```sh
bazel run //tools/secret-scan                     # this branch's commits that main does not have
bazel run //tools/secret-scan -- --staged         # what a commit would record right now
bazel run //tools/secret-scan -- --range <a..b>   # a range of commits
bazel run //tools/secret-scan -- --unpushed       # commits origin does not have yet
```

A finding names the file, the line, the rule and (for commits) the commit. It
never prints the secret: gitleaks' own output, which quotes the text around a
finding, is kept off the screen.

Exit codes: `0` nothing found, `1` something found, `2` the scan could not run.
A scan that could not run is never reported as clean.

`//tools/git:commit` runs `--staged` before every commit, and `//tools/git:push`
runs `--unpushed` before every push.

## Where the pin lives

gitleaks is pinned in [`tools/tools.lock.json`](../tools.lock.json) (multitool),
for Linux and macOS. CI's `//tools/ci:secret_scan`
([source](../ci/src/secret_scan/lib.rs)) downloads its own copy.
`bazel test //tools/ci:secret_scan_test` fails when the two versions, or the
Linux checksums, disagree, so update both together.

## What to do with a finding

- **A real secret:** take it out. If it was ever pushed, rotate it as well;
  rewriting history does not un-share it.
- **A false positive that is safe by construction:** add a scoped allowlist
  entry to `.gitleaks.toml` saying why, or put `gitleaks:allow` on that line.
- **Already committed on your branch:** fix it in a new commit and fold it in:
  `bazel run //tools/git:commit -- --fixup <sha> <file>`, then
  `bazel run //tools/git:sync -- --autosquash`.
