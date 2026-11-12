"""Re-lock pnpm-lock.yaml after editing a package.json.

  bazel run //tools/pnpm:lock              # after editing any package.json in the workspace
  bazel run //tools/pnpm:lock -- --check   # is pnpm-lock.yaml in step? changes nothing, exits 1 if not

To add, remove or bump a JavaScript dependency, edit the package.json by hand
(exact version or range), then run :lock. There is deliberately no `add`:
`pnpm add` installs node_modules even with --lockfile-only (pnpm 10.20.0).

Raw `pnpm`/`npm` is blocked for agents (tools/agent-guard). This runs the pnpm
version the root package.json pins (`packageManager`, via @pnpm) from the repo
root, always with --lockfile-only and --ignore-scripts: it writes only
pnpm-lock.yaml, never node_modules, and runs no package's install scripts.
Bazel (rules_js) installs packages itself when you build or test.
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

sh_binary(
    name = "lock",
    srcs = ["lock.sh"],
    data = ["@pnpm"],
    env = {"PNPM_BIN": "$(rlocationpath @pnpm)"},
    visibility = ["//visibility:public"],
    deps = ["@bazel_tools//tools/bash/runfiles"],
)
