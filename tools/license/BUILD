# License header enforcement via addlicense.
#
# Usage:
#   bazel run //tools/license:add    — add/fix missing MIT headers
#   bazel run //tools/license:check  — verify all headers present (non-zero if missing)
#
# Both are `bazel run` targets (not `bazel test`): `:check` must run in the live
# source tree, which a `bazel test` sandbox does not have. A generated launcher
# cd's to $BUILD_WORKSPACE_DIRECTORY before invoking addlicense so it scans the
# real workspace. CI (.github/workflows/ci.yaml license-check job) calls
# `bazel run //tools/license:check`; addlicense is hermetic via multitool
# (@multitool//tools/addlicense), replacing the old `go install` step.
#
# The flags + ignore set mirror the previous CI invocation 1:1 (addlicense v1.2.0,
# -c VitruvianSoftware -l mit), so `:check` is behavior-identical to the prior gate.

load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("//tools/license:defs.bzl", "addlicense_run_target")

# Glob patterns passed as -ignore flags to addlicense — generated / tool-managed
# files that must not receive license headers. Kept in sync with what the CI
# license-check job ignored before this moved to Bazel.
_IGNORE_GLOBS = [
    # gazelle-owned / generated build files
    "**/BUILD",
    "**/BUILD.bazel",
    # docs + scaffold template payloads (not source)
    "**/docs/**",
    "**/internal/scaffold/templates/**",
    # lockfiles + generated manifests
    "pnpm-lock.yaml",
    "**/package-lock.json",
    "**/Cargo.lock",
    "MODULE.bazel.lock",
    "**/gazelle_python.yaml",
    "**/*-baseline.xml",
    "**/.release-please-manifest.json",
    # Pulumi per-stack config (tool-managed; matches Pulumi.dev.yaml etc.)
    "**/Pulumi.*.yaml",
    # dev-local vendored manifests + dashboards
    "**/dev-local/crds/**",
    "**/dev-local/values/**",
    "**/dev-local/dashboards/**",
    # generated DB migrations
    "**/prisma/migrations/**",
    # bazel symlinks, vendored trees, VCS
    "bazel-*/**",
    "**/node_modules/**",
    "**/*.venv/**",
    ".git/**",
    # generated / local-only (gitignored; never in a CI checkout, but excluded so
    # `bazel run //tools/license:{add,check}` is clean on a developer's tree too)
    "**/coverage/**",
    ".remember/**",
    "**/lima-k8s.yaml",
]

_LICENSE_FLAG = "mit"

_COPYRIGHT = "VitruvianSoftware"

# bazel run //tools/license:add — write/fix missing MIT headers.
addlicense_run_target(
    name = "add",
    check_mode = False,
    copyright = _COPYRIGHT,
    ignore_globs = _IGNORE_GLOBS,
    license_flag = _LICENSE_FLAG,
    visibility = ["//visibility:public"],
)

# bazel run //tools/license:check — exit non-zero if any headers are missing.
addlicense_run_target(
    name = "check",
    check_mode = True,
    copyright = _COPYRIGHT,
    ignore_globs = _IGNORE_GLOBS,
    license_flag = _LICENSE_FLAG,
    visibility = ["//visibility:public"],
)

bzl_library(
    name = "defs",
    srcs = ["defs.bzl"],
    visibility = ["//visibility:public"],
)
