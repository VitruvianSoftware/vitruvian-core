"""Look for secrets with the gitleaks and the rules CI uses.

  bazel run //tools/secret-scan                     # this branch's commits that main lacks
  bazel run //tools/secret-scan -- --staged         # what a commit would record now
  bazel run //tools/secret-scan -- --range <a..b>   # a range of commits
  bazel run //tools/secret-scan -- --unpushed       # commits origin does not have yet

gitleaks is pinned in tools/tools.lock.json at the version CI's
tools/ci/secret-scan.sh downloads (the test fails if the two drift apart), and
the rules are the repo's .gitleaks.toml. //tools/git:commit and :push call this
before they record or publish anything.
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

# //tools/git runs this script from its own runfiles.
exports_files(["secret-scan.sh"])

sh_binary(
    name = "secret-scan",
    srcs = ["secret-scan.sh"],
    data = [
        "//:.gitleaks.toml",
        "@multitool//tools/gitleaks",
    ],
    visibility = ["//visibility:public"],
    deps = ["@bazel_tools//tools/bash/runfiles"],
)

# Throwaway repos and the real pinned gitleaks: no network, never the real repo.
sh_test(
    name = "secret-scan_test",
    size = "small",
    srcs = ["secret-scan_test.sh"],
    args = [
        "$(location secret-scan.sh)",
        "$(location //tools/ci:secret-scan.sh)",
        "$(location //tools:tools.lock.json)",
    ],
    data = [
        "secret-scan.sh",
        "//:.gitleaks.toml",
        "//tools:tools.lock.json",
        "//tools/ci:secret-scan.sh",
        "@multitool//tools/gitleaks",
    ],
    deps = ["@bazel_tools//tools/bash/runfiles"],
)
