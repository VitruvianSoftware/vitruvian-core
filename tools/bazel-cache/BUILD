"""Local Bazel cache upkeep (developer-machine only; nothing here runs in CI).

  bazel run //tools/bazel-cache:gc          # DRY-RUN: list reclaimable output_bases
  bazel run //tools/bazel-cache:gc -- --execute

.bazelrc pins `common --repository_cache=~/.cache/bazel/repository-cache` so the
downloaded-archive cache is shared across every output_base. Without it,
//tools/worktree's per-worktree `--output_user_root` (issue #455) relocates the
download cache too and every worktree re-downloads everything: measured 193s +
9.7GB for `bazel build //devx:devx` in a fresh root, versus 65s + 0 downloaded
when the cache is shared.
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["bazel-cache.sh"])

sh_binary(
    name = "gc",
    srcs = ["bazel-cache.sh"],
    args = ["gc"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "bazel-cache_test",
    size = "small",
    srcs = ["bazel-cache_test.sh"],
    data = ["bazel-cache.sh"],
)
