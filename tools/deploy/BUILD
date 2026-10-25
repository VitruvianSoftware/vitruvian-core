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

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

# Exported so per-app cloud_run_deploy(...) targets in other packages can list it
# in srcs (same pattern as //tools/pulumi:pulumi_cmd.sh).
exports_files(["cloud-run.sh"])

# The sequencer, in Rust (src/): cloud-run.sh's flags, output, exit codes and
# its pulumi / gcloud / curl calls (with the <PREFIX>_ variables they are
# handed), held to the script by the parity test below. The candidate URL is
# read from gcloud's JSON with serde_json where the script used jq.
rust_library(
    name = "deploy_lib",
    srcs = ["src/lib.rs"],
    crate_name = "deploy",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
        "@crates//:serde_json",
    ],
)

# Generic sequencer: the operator passes every parameter as a flag.
rust_binary(
    name = "cloud-run",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [
        ":deploy_lib",
        "//tools/shell-compat:shell_compat",
    ],
)

[
    alias(
        name = name,
        actual = ":cloud-run",
        visibility = ["//visibility:public"],
    )
    for name in [
        "cloud-run-rs",
        "cloud_run_rs",
    ]
]

# The shell original, kept runnable and held to the port by the parity test.
# (cloud_run_deploy in defs.bzl still wraps the script itself.)
sh_binary(
    name = "cloud-run-sh",
    srcs = ["cloud-run.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "cloud-run_test",
    srcs = ["cloud-run_test.sh"],
    args = ["$(location cloud-run.sh)"],
    data = ["cloud-run.sh"],
)

# The same suite against the Rust binary (CLOUD_RUN_BIN). The checks that
# source the script for its pure functions run against the script only; the
# port's are :deploy_lib_test.
sh_test(
    name = "cloud-run-rs_test",
    srcs = ["cloud-run_test.sh"],
    args = ["$(location cloud-run.sh)"],
    data = [
        "cloud-run.sh",
        ":cloud-run",
    ],
    env = {"CLOUD_RUN_BIN": "$(rootpath :cloud-run)"},
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "deploy_lib_test",
    size = "small",
    crate = ":deploy_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Script and binary side by side on every case in cloud_run_rs_parity_test.py:
# exit code, stdout, stderr, and every pulumi / gcloud / curl / custom-smoke
# call (argv and the <PREFIX>_ variables in its environment), compared byte
# for byte. The script filters gcloud's JSON with jq; the remote-exec image
# has none, so the hermetic one is brought along.
py_test(
    name = "cloud_run_rs_parity_test",
    size = "medium",
    srcs = ["cloud_run_rs_parity_test.py"],
    data = [
        "cloud-run.sh",
        ":cloud-run",
        "@jq_toolchains//:resolved_toolchain",
    ],
    env = {
        "CLOUD_RUN_RS": "$(rootpath :cloud-run)",
        "CLOUD_RUN_SH": "$(rootpath cloud-run.sh)",
        "JQ_BIN": "$(JQ_BIN)",
    },
    main = "cloud_run_rs_parity_test.py",
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
    deps = ["//tools/shell-compat:parity_harness"],
)
