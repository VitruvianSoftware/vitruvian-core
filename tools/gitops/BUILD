"""GitOps `bazel run` wrappers — kubectl behind bazel (see defs.bzl).

Generic passthroughs forward manifests via `-- -f <path>`:
    bazel run //tools/gitops:apply -- -f gitops/argocd/root-projects.yaml
    bazel run //tools/gitops:status
Per-component declared targets come from the gitops_manifest macro.

Every tool target below runs the Rust port (src/ops/, one module per script,
behind src/bin/gitops_cli.rs); the shell original stays runnable as
<target>-sh, and :gitops_rs_parity_test holds the two together.
"""

# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files([
    "gitops-cmd.sh",
    "fedora_power_cycle.py",
])

# Out-of-band power-cycle utility for host `fedora` via Kasa HS300 smart power strip.
#   bazel run //tools/gitops:fedora-power-cycle -- --status
#   bazel run //tools/gitops:fedora-power-cycle -- --cycle
#   bazel run //tools/gitops:fedora-power-cycle -- --host 192.168.86.48 --off
# The default target is the Rust port (src/); the Python original stays as
# :fedora-power-cycle-py, and the parity test holds the two together.
py_binary(
    name = "fedora-power-cycle-py",
    srcs = ["fedora_power_cycle.py"],
    main = "fedora_power_cycle.py",
    visibility = ["//visibility:public"],
)

# The one Rust library of this package (//tools/lint-naming allows one per
# directory), holding two things:
#   - fedora_power_cycle.py in Rust, standard library only: the same flags,
#     help and errors (src/argparse.rs is Python 3.12's argparse), the same
#     JSON bytes to the strip (src/json.rs writes what json.dumps writes), the
#     same XOR framing, output and exit codes;
#   - src/ops/: the 13 shell tools below in Rust. JSON (bw, kubectl,
#     Prometheus, Tempo, ArgoCD) is read and written with serde_json where
#     the scripts used jq or python3; the bash behaviours they rely on come
#     from //tools/shell-compat.
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

# Holds the Rust binary to the Python script: both run as programs against
# one fake HS300 on localhost, comparing exit codes, stdout, stderr and the
# exact commands each sent, across --status/--on/--off/--cycle, strips that
# answer badly, and command lines argparse treats specially.
py_test(
    name = "fedora_power_cycle_rs_parity_test",
    size = "small",
    srcs = [
        "fedora_power_cycle.py",
        "fedora_power_cycle_rs_parity_test.py",
    ],
    data = [":fedora-power-cycle"],
    env = {"FEDORA_POWER_CYCLE_RS": "$(rootpath :fedora-power-cycle)"},
    imports = ["."],
    main = "fedora_power_cycle_rs_parity_test.py",
)

# ---------------------------------------------------------------------------
# The shell tools, in Rust.
#
# One binary, src/bin/gitops_cli.rs: `gitops-cli TOOL ARGS...` runs TOOL as
# `bash TOOL.sh ARGS...` would. Each target below is that binary with the
# tool (and subcommand) baked into its args, under the target name the shell
# script had. `<target>-sh` runs the shell original; `<target>-rs` names the
# port explicitly.
# ---------------------------------------------------------------------------

rust_binary(
    name = "gitops-cli",
    srcs = ["src/bin/gitops_cli.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":fedora_power_cycle_lib"],
)

# target name -> (script, the script's baked-in args). The Rust binary gets
# the tool name first (TOOL_OF), then the same args.
#
# gitops-cmd.sh: kubectl (and helm, kubeseal) against the dev-local cluster,
# from the workspace root. Generic passthroughs forward `-- ARGS`:
#   bazel run //tools/gitops:apply -- -f gitops/argocd/root-projects.yaml
#   bazel run //tools/gitops:status
#
# seal-alert-ntfy: seal the ntfy alert-delivery password Alertmanager reads
# (SealedSecret alertmanager-ntfy-endpoint/ntfy-password in `monitoring`).
#   bazel run //tools/gitops:seal-alert-ntfy -- 'the-password' [--apply]
#
# seal-argocd-backstage-token: mint AND seal the read-only ArgoCD token the
# Backstage ArgoCD cards use; it never passes through a clipboard. Needs the
# `backstage` role on platform-project merged and synced first.
#   bazel run //tools/gitops:seal-argocd-backstage-token [-- --apply]
#
# seal-headplane-secret: generate and seal headplane's 32-char cookie_secret
# (SealedSecret headplane-secret/cookie-secret in `headscale`).
#   bazel run //tools/gitops:seal-headplane-secret [-- --apply]
#
# seal-zitadel-login-cookie-secret: generate + seal the Zitadel Login UI
# session-cookie signing secret. Re-running rotates it and signs every user
# out of the Login UI -- see the script header.
#
# sealed-secrets-{backup,restore,verify}: the sealed-secrets controller
# private keys to/from Bitwarden (verify is read-only). Unlock is automatic
# (prompts for the master password if locked); `bw login` once first.
#
# argocd-secret-{backup,restore,verify}: the ArgoCD argocd-secret
# (server.secretkey + mcp token seed) to/from Bitwarden. ArgoCD is the pulumi
# bootstrap, so its secret can't be a SealedSecret.
#
# ntfy-bootstrap-users: one-time creation of the alertmanager (write-only)
# and james (read-only) ntfy users that auth-default-access: deny-all needs.
#   bazel run //tools/gitops:ntfy-bootstrap-users -- vitruvian-alerts
#
# ntfy-user-*: ntfy account lifecycle (list/add/del/change-pass/change-role/
# access). ntfy-rotate-ci-password rotates the password CI's
# notify-ci-issues workflow logs in with: to the pod and the repo secret,
# checked against the live server, never printed.
#   bazel run //tools/gitops:ntfy-user-add -- USERNAME [admin|user]
#   bazel run //tools/gitops:ntfy-user-access -- USERNAME TOPIC PERMISSION
#
# headscale*: Headscale/Headplane operations in the headscale pod: API keys,
# users, node registrations, pre-auth keys.
#   bazel run //tools/gitops:headscale -- <args...>
#   bazel run //tools/gitops:headscale-node-register -- --user <u> --key <nodekey>
#
# rotate-github-otel-webhook-secret: generate the GitHub -> CI-collector
# webhook secret and put it in both places, never printed: sealed into git
# for the collector, and the GitHub secret OTEL_GITHUB_WEBHOOK_SECRET
# (Actions + Dependabot). Re-run to rotate.
#
# cicd-telemetry-smoke: gate for the CI collector (spec §4): unsigned POST ->
# 400; a correctly signed sample workflow_run event -> a trace in Tempo and a
# metric in Prometheus. Reads the secret from the cluster; never prints it.
#
# seal-arc-github-app: seal the vitruvian-arc GitHub App's credentials for
# the merge-queue runners.
#   bazel run //tools/gitops:seal-arc-github-app [-- --apply]
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

# The Rust tool name for each script (src/ops/mod.rs TOOLS).
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

# The shell originals, kept runnable and held to the port by the parity test.
[
    sh_binary(
        name = name + "-sh",
        srcs = [script],
        args = args,
        visibility = ["//visibility:public"],
    )
    for name, (script, args) in TOOLS.items()
]

# Every kubeseal call in the shell tools passes --context (the Rust port
# builds every kubeseal command through one function that adds it; see
# src/ops/common.rs and its unit test).
sh_test(
    name = "kubeseal_context_test",
    size = "small",
    srcs = ["kubeseal_context_test.sh"],
    data = glob(
        ["*.sh"],
        exclude = ["*_test.sh"],
    ),
)

# Each hermetic shell test runs twice: against the script, and (the -rs_test)
# against the Rust port, named by an environment variable the test reads.
sh_test(
    name = "ntfy_manage_users_test",
    size = "small",
    srcs = ["ntfy_manage_users_test.sh"],
    data = ["ntfy_manage_users.sh"],
)

sh_test(
    name = "ntfy-manage-users-rs_test",
    size = "small",
    srcs = ["ntfy_manage_users_test.sh"],
    data = [
        "ntfy_manage_users.sh",
        ":gitops-cli",
    ],
    env = {"NTFY_MANAGE_USERS_BIN": "$(rootpath :gitops-cli)"},
)

sh_test(
    name = "rotate_github_otel_webhook_secret_test",
    size = "small",
    srcs = ["rotate_github_otel_webhook_secret_test.sh"],
    data = ["rotate_github_otel_webhook_secret.sh"],
)

sh_test(
    name = "rotate-github-otel-webhook-secret-rs_test",
    size = "small",
    srcs = ["rotate_github_otel_webhook_secret_test.sh"],
    data = [
        "rotate_github_otel_webhook_secret.sh",
        ":gitops-cli",
    ],
    env = {"ROTATE_GITHUB_OTEL_WEBHOOK_SECRET_BIN": "$(rootpath :gitops-cli)"},
)

sh_test(
    name = "cicd_telemetry_smoke_test",
    size = "small",
    srcs = ["cicd_telemetry_smoke_test.sh"],
    data = [
        "cicd_telemetry_smoke.sh",
        "@jq_toolchains//:resolved_toolchain",
    ],
    # The script needs jq; the remote-exec image has none, so bring our own.
    env = {"JQ_BIN": "$(JQ_BIN)"},
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
)

# No jq here: the port reads the JSON itself, and this proves it.
sh_test(
    name = "cicd-telemetry-smoke-rs_test",
    size = "small",
    srcs = ["cicd_telemetry_smoke_test.sh"],
    data = [
        "cicd_telemetry_smoke.sh",
        ":gitops-cli",
    ],
    env = {"CICD_TELEMETRY_SMOKE_BIN": "$(rootpath :gitops-cli)"},
)

sh_test(
    name = "seal_arc_github_app_test",
    size = "small",
    srcs = ["seal_arc_github_app_test.sh"],
    data = ["seal_arc_github_app.sh"],
)

sh_test(
    name = "seal-arc-github-app-rs_test",
    size = "small",
    srcs = ["seal_arc_github_app_test.sh"],
    data = [
        "seal_arc_github_app.sh",
        ":gitops-cli",
    ],
    env = {"SEAL_ARC_GITHUB_APP_BIN": "$(rootpath :gitops-cli)"},
)

# Side by side: every one of the 13 tools runs as `bash <script>` and as the
# Rust binary, in identical sandboxes of fake kubectl/kubeseal/bw/gh/curl/
# openssl/python3, comparing exit code, stdout, stderr, every file left
# behind, and everything the fakes were called with (argv and stdin).
py_test(
    name = "gitops_rs_parity_test",
    size = "medium",
    srcs = ["gitops_rs_parity_test.py"],
    data = [
        ":gitops-cli",
        "@jq_toolchains//:resolved_toolchain",
    ] + glob(
        ["*.sh"],
        exclude = ["*_test.sh"],
    ),
    env = {
        "GITOPS_CLI": "$(rootpath :gitops-cli)",
        "JQ_BIN": "$(JQ_BIN)",
    },
    main = "gitops_rs_parity_test.py",
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
    deps = ["//tools/shell-compat:parity_harness"],
)
