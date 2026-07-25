"""Scan this repo's lockfiles for known advisories (OSV database).

  bazel run //tools/osv-scan

Replaces GitHub's `dependency-review`, which reads GitHub's dependency graph --
an Advanced Security feature that is free on public repos but billed per active
committer on private ones, and (verified against the API) cannot be enabled
without `advanced_security`. osv-scanner reads the lockfiles directly, so it
costs nothing at any visibility, runs locally as well as in CI, and also covers
Cargo and PyPI. See tools/osv-scan/osv-scan.sh for the full rationale.
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

sh_binary(
    name = "osv-scan",
    srcs = ["osv-scan.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "osv-scan_test",
    size = "small",
    srcs = ["osv-scan_test.sh"],
    data = ["osv-scan.sh"],
)
