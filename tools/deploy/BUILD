# gazelle:exclude defs.bzl
#
# Local + CI deploy tooling: the blue-green Cloud Run rollout as a bazel target.
#
# //tools/deploy:cloud-run runs the candidate -> smoke -> promote sequence for a
# Cloud Run app stack, reusing //tools/pulumi:pulumi_cmd.sh for the apply (so
# auth, GCP identity, and the Pulumi backend resolve exactly as `bazel run
# //<app>:up`). It is the single source of truth the reusable deploy workflow
# calls, so the same rollout runs from a workstation when GitHub Actions is down.
#
# cloud_run_deploy (defs.bzl) bakes an app's fixed params into a per-app :deploy
# target, e.g. `bazel run //tabula/infra/app:deploy -- --env development
# --project <p> --image-digest <d>`. defs.bzl is gazelle:exclude'd (no
# bzl_library) to match //tools/pulumi:defs.bzl and //tools/oci.

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# The sequencer, in Rust (src/).
rust_library(
    name = "deploy_lib",
    srcs = ["src/lib.rs"],
    crate_name = "deploy",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    # tabula-deploy-preflight reuses serving_revision, so both agree on "live".
    visibility = ["//tools/ci:__pkg__"],
    deps = [
        "//tools/shell-compat:shell_compat",
        "@crates//:serde_json",
    ],
)

# Generic sequencer: the operator passes every parameter as a flag.
rust_binary(
    name = "cloud-run",
    srcs = ["src/main.rs"],
    # It runs tools/pulumi/pulumi-cmd.sh, which inherits this and mints GCP
    # tokens with //tools/gcp-token, as the pulumi_project() targets do.
    data = ["//tools/gcp-token"],
    edition = "2021",
    env = {"VITRUVIAN_GCP_TOKEN_BIN": "$(rootpath //tools/gcp-token)"},
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":deploy_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

# Generated launcher so per-app cloud_run_deploy(...) sh_binary targets in
# other packages can list `//tools/deploy:cloud-run.sh` in srcs.
genrule(
    name = "cloud_run_sh_shim",
    srcs = [":cloud-run"],
    outs = ["cloud-run.sh"],
    cmd = "printf '%s\\n' '#!/usr/bin/env bash' 'exec \"$$(cd \"$$(dirname \"$${BASH_SOURCE[0]}\")\" && pwd)/cloud-run\" \"$$@\"' > $@ && chmod +x $@",
    executable = True,
    visibility = ["//visibility:public"],
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "deploy_lib_test",
    size = "small",
    crate = ":deploy_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "cloud-run_test",
    tests = [":deploy_lib_test"],
)
