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

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

# Exported so per-app cloud_run_deploy(...) targets in other packages can list it
# in srcs (same pattern as //tools/pulumi:pulumi_cmd.sh).
exports_files(["cloud-run.sh"])

# Generic sequencer: the operator passes every parameter as a flag.
sh_binary(
    name = "cloud-run",
    srcs = ["cloud-run.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "cloud-run_test",
    srcs = ["cloud-run_test.sh"],
    args = ["$(location cloud-run.sh)"],
    data = ["cloud-run.sh"],
)
