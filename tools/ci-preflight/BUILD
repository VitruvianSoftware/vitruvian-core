"""What CI requires, and what is actually configured.

  bazel run //tools/ci-preflight            # report; non-zero if required is missing
  bazel run //tools/ci-preflight -- --list  # just the required set, no network

`//:doctor` answers "can I build this repo on THIS machine". This answers the
other half -- "is the REPO wired up so CI can actually run" -- which fails in a
nastier way, because a missing secret is not an error but an empty string.

The required set is DERIVED from every `secrets.X` / `vars.X` in
.github/workflows and .github/actions, so it cannot drift from the workflows it
describes. Its sharpest check is the Dependabot one: a secret read by a
`pull_request`-triggered workflow resolves to the empty string on Dependabot PRs
unless it also exists in the separate Dependabot store -- which is exactly how
#1164 failed. See tools/ci-preflight/ci-preflight.sh for the full rationale.

Deliberately NOT wired into CI as a gate: it reads repo configuration state that
lives outside the commit, so it would fail on forks and on any run whose token
lacks admin:repo. It is a developer/maintainer preflight, run on demand.
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

sh_binary(
    name = "ci-preflight",
    srcs = ["ci-preflight.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "ci-preflight_test",
    size = "small",
    srcs = ["ci-preflight_test.sh"],
    data = ["ci-preflight.sh"],
)
