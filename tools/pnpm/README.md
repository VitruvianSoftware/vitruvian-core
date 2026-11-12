# pnpm

## Overview
`bazel run //tools/pnpm:lock` re-locks `pnpm-lock.yaml` after you edit a
`package.json`, using the pnpm version the root `package.json` pins.
`-- --check` only reports whether the lockfile is in step.

It always passes `--lockfile-only --ignore-scripts`, so it writes only the
lockfile: no `node_modules`, and no package install scripts. Bazel (rules_js)
installs packages itself when you build or test. There is no `add`: edit the
manifest by hand, then re-lock (`pnpm add` installs even with
`--lockfile-only`).

Raw `pnpm`/`npm` is blocked for agents by
[agent-guard](../agent-guard/README.md), which points here instead.
