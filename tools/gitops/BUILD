# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""GitOps `bazel run` wrappers — kubectl behind bazel (see defs.bzl).

Generic passthroughs forward manifests via `-- -f <path>`:
    bazel run //tools/gitops:apply -- -f gitops/argocd/root-projects.yaml
    bazel run //tools/gitops:status
Per-component declared targets come from the gitops_manifest macro.

Every tool target below runs the Rust implementation (src/ops/, one module per
tool, behind src/bin/gitops_cli.rs).
"""

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# Out-of-band power-cycle utility for host `fedora` via Kasa HS300 smart power strip.
#   bazel run //tools/gitops:fedora-power-cycle -- --status
#   bazel run //tools/gitops:fedora-power-cycle -- --cycle
#   bazel run //tools/gitops:fedora-power-cycle -- --host 192.168.86.48 --off
alias(
    name = "fedora-power-cycle-py",
    actual = ":fedora-power-cycle",
    visibility = ["//visibility:public"],
)

# The one Rust library of this package (//tools/lint-naming allows one per
# directory), holding two things:
#   - fedora-power-cycle in Rust, standard library only;
#   - src/ops/: the 13 GitOps tools below in Rust. JSON (bw, kubectl,
#     Prometheus, Tempo, ArgoCD) is read and written with serde_json; the bash
#     behaviours they rely on come from //tools/shell-compat.
# Optimised in every build mode.
rust_library(
    name = "fedora_power_cycle_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = [
            "src/main.rs",
            "src/bin/**",
        ],
    ),
    crate_name = "fedora_power_cycle",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "//tools/shell-compat:shell_compat",
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "fedora-power-cycle",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":fedora_power_cycle_lib"],
)

alias(
    name = "fedora-power-cycle-rs",
    actual = ":fedora-power-cycle",
    visibility = ["//visibility:public"],
)

alias(
    name = "fedora_power_cycle_rs",
    actual = ":fedora-power-cycle",
    visibility = ["//visibility:public"],
)

# The #[cfg(test)] unit tests in src/: a loopback strip, and the ops modules'
# jq filters, HMAC-SHA256, base64 and bash emulations.
rust_test(
    name = "fedora_power_cycle_lib_test",
    size = "small",
    crate = ":fedora_power_cycle_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "fedora_power_cycle_rs_parity_test",
    tests = [":fedora_power_cycle_lib_test"],
)

# ---------------------------------------------------------------------------
# The GitOps tools, in Rust.
#
# One binary, src/bin/gitops_cli.rs: `gitops-cli TOOL ARGS...` runs TOOL.
# Each target below is that binary with the tool (and subcommand) baked into
# its args.
# ---------------------------------------------------------------------------

rust_binary(
    name = "gitops-cli",
    srcs = ["src/bin/gitops_cli.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":fedora_power_cycle_lib"],
)

# Consumed by gitops_manifest() in defs.bzl as srcs = ["//tools/gitops:gitops-cmd.sh"].
genrule(
    name = "gitops_cmd_sh_shim",
    srcs = [":gitops-cli"],
    outs = ["gitops-cmd.sh"],
    cmd = "printf '%s\\n' '#!/usr/bin/env bash' " +
          "'_dir=\"$$(cd \"$$(dirname \"$${BASH_SOURCE[0]}\")\" && pwd)\"' " +
          "'if [ -x \"$$_dir/gitops-cli\" ]; then exec \"$$_dir/gitops-cli\" gitops-cmd \"$$@\"; fi' " +
          "'exec \"$${RUNFILES_DIR:-$$0.runfiles}/_main/tools/gitops/gitops-cli\" gitops-cmd \"$$@\"' > $@ && chmod +x $@",
    executable = True,
    visibility = ["//visibility:public"],
)

TOOLS = {
    "apply": (
        "gitops-cmd.sh",
        ["apply"],
    ),
    "delete": (
        "gitops-cmd.sh",
        ["delete"],
    ),
    "diff": (
        "gitops-cmd.sh",
        ["diff"],
    ),
    "get": (
        "gitops-cmd.sh",
        ["get"],
    ),
    "patch": (
        "gitops-cmd.sh",
        ["patch"],
    ),
    "status": (
        "gitops-cmd.sh",
        ["status"],
    ),
    "helm": (
        "gitops-cmd.sh",
        ["helm"],
    ),
    "kubeseal": (
        "gitops-cmd.sh",
        ["kubeseal"],
    ),
    "seal-alert-ntfy": ("seal_alert_ntfy.sh", []),
    "seal-argocd-backstage-token": ("seal_argocd_backstage_token.sh", []),
    "seal-headplane-secret": ("seal_headplane_secret.sh", []),
    "seal-zitadel-login-cookie-secret": ("seal_zitadel_login_cookie_secret.sh", []),
    "sealed-secrets-backup": (
        "sealed_secrets_keys.sh",
        ["backup"],
    ),
    "sealed-secrets-restore": (
        "sealed_secrets_keys.sh",
        ["restore"],
    ),
    "sealed-secrets-verify": (
        "sealed_secrets_keys.sh",
        ["verify"],
    ),
    "argocd-secret-backup": (
        "argocd-secret.sh",
        ["backup"],
    ),
    "argocd-secret-restore": (
        "argocd-secret.sh",
        ["restore"],
    ),
    "argocd-secret-verify": (
        "argocd-secret.sh",
        ["verify"],
    ),
    "ntfy-bootstrap-users": ("ntfy_bootstrap_users.sh", []),
    "ntfy-user-list": (
        "ntfy_manage_users.sh",
        ["list"],
    ),
    "ntfy-user-add": (
        "ntfy_manage_users.sh",
        ["add"],
    ),
    "ntfy-user-del": (
        "ntfy_manage_users.sh",
        ["del"],
    ),
    "ntfy-user-change-pass": (
        "ntfy_manage_users.sh",
        ["change-pass"],
    ),
    "ntfy-rotate-ci-password": (
        "ntfy_manage_users.sh",
        [
            "change-pass",
            "github-actions",
            "--gh-secret",
            "NTFY_GITHUB_ACTIONS_PASSWORD",
        ],
    ),
    "ntfy-user-change-role": (
        "ntfy_manage_users.sh",
        ["change-role"],
    ),
    "ntfy-user-access": (
        "ntfy_manage_users.sh",
        ["access"],
    ),
    "headscale": (
        "headscale_ops.sh",
        ["raw"],
    ),
    "headscale-apikey-create": (
        "headscale_ops.sh",
        ["apikey-create"],
    ),
    "headscale-apikey-list": (
        "headscale_ops.sh",
        ["apikey-list"],
    ),
    "headscale-apikey-expire": (
        "headscale_ops.sh",
        ["apikey-expire"],
    ),
    "headscale-user-create": (
        "headscale_ops.sh",
        ["user-create"],
    ),
    "headscale-user-list": (
        "headscale_ops.sh",
        ["user-list"],
    ),
    "headscale-user-destroy": (
        "headscale_ops.sh",
        ["user-destroy"],
    ),
    "headscale-node-list": (
        "headscale_ops.sh",
        ["node-list"],
    ),
    "headscale-node-register": (
        "headscale_ops.sh",
        ["node-register"],
    ),
    "headscale-node-delete": (
        "headscale_ops.sh",
        ["node-delete"],
    ),
    "headscale-preauthkey-create": (
        "headscale_ops.sh",
        ["preauthkey-create"],
    ),
    "headscale-preauthkey-list": (
        "headscale_ops.sh",
        ["preauthkey-list"],
    ),
    "rotate-github-otel-webhook-secret": ("rotate_github_otel_webhook_secret.sh", []),
    "cicd-telemetry-smoke": ("cicd_telemetry_smoke.sh", []),
    "seal-arc-github-app": ("seal_arc_github_app.sh", []),
}

# The Rust tool name for each tool (src/ops/mod.rs TOOLS).
TOOL_OF = {
    "argocd-secret.sh": "argocd-secret",
    "cicd_telemetry_smoke.sh": "cicd-telemetry-smoke",
    "gitops-cmd.sh": "gitops-cmd",
    "headscale_ops.sh": "headscale-ops",
    "ntfy_bootstrap_users.sh": "ntfy-bootstrap-users",
    "ntfy_manage_users.sh": "ntfy-manage-users",
    "rotate_github_otel_webhook_secret.sh": "rotate-github-otel-webhook-secret",
    "seal_alert_ntfy.sh": "seal-alert-ntfy",
    "seal_arc_github_app.sh": "seal-arc-github-app",
    "seal_argocd_backstage_token.sh": "seal-argocd-backstage-token",
    "seal_headplane_secret.sh": "seal-headplane-secret",
    "seal_zitadel_login_cookie_secret.sh": "seal-zitadel-login-cookie-secret",
    "sealed_secrets_keys.sh": "sealed-secrets-keys",
}

[
    rust_binary(
        name = name,
        srcs = ["src/bin/gitops_cli.rs"],
        args = [TOOL_OF[script]] + args,
        edition = "2021",
        rustc_flags = ["-Copt-level=3"],
        visibility = ["//visibility:public"],
        deps = [":fedora_power_cycle_lib"],
    )
    for name, (script, args) in TOOLS.items()
]

[
    alias(
        name = name + "-rs",
        actual = ":" + name,
        visibility = ["//visibility:public"],
    )
    for name in TOOLS
]

[
    alias(
        name = name + "-sh",
        actual = ":" + name,
        visibility = ["//visibility:public"],
    )
    for name in TOOLS
]

[
    test_suite(
        name = test_name,
        tests = [":fedora_power_cycle_lib_test"],
    )
    for test_name in [
        "kubeseal_context_test",
        "ntfy_manage_users_test",
        "ntfy-manage-users-rs_test",
        "rotate_github_otel_webhook_secret_test",
        "rotate-github-otel-webhook-secret-rs_test",
        "cicd_telemetry_smoke_test",
        "cicd-telemetry-smoke-rs_test",
        "seal_arc_github_app_test",
        "seal-arc-github-app-rs_test",
        "gitops_rs_parity_test",
    ]
]
