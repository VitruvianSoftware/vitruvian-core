"""Bootstrap a Claude Code *cloud* sandbox into a vitruvian-core dev machine.

A cloud session starts as a bare Ubuntu box: git, go and node, but no bazel, no
gh, no gcloud, no pulumi -- and no credentials for any of them. This installs
what has to exist before `bazel run` works, then establishes exactly the
credentials the session's PROFILE is allowed to hold.

  bazel run //tools/cloud-bootstrap                # install + authenticate
  bazel run //tools/cloud-bootstrap:whoami         # report; non-zero if unsatisfied
  bazel run //tools/cloud-bootstrap:profiles       # list the declared profiles

$VITRUVIAN_PROFILE (set on the cloud environment) selects one row of
profiles.tsv, and that row is the blast-radius boundary: it decides which CLIs
are installed and which secrets the session may materialise. The only credential
the environment needs is $PULUMI_ACCESS_TOKEN: bootstrap uses it to get a short-lived
GCP token from Pulumi ESC (the org forbids service-account keys,
iam.disableServiceAccountKeyCreation) and reads the rest from Secret Manager at
session start (see README.md, "Two knobs").

It is also the first step of the SessionStart hook, .claude/session-start.sh,
which is how it actually runs. The `bazel run` targets exist because the hook cannot be
the only way to exercise it -- `:whoami` is how an operator (or the agent) proves
what the session actually holds without printing a single secret value.

See tools/cloud-bootstrap/README.md and docs/admin/claude-code-cloud-sessions.md.
"""

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files([
    "cloud-bootstrap.sh",
    "profiles.tsv",
])

# The calling sh_binary bakes the subcommand as $1 (mirrors //tools/saas-cli and
# //tools/sync-env-secrets). Flags a developer appends after `--` are forwarded.
sh_binary(
    name = "cloud-bootstrap",
    srcs = ["cloud-bootstrap.sh"],
    args = ["up"],
    data = ["profiles.tsv"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "install",
    srcs = ["cloud-bootstrap.sh"],
    args = ["install"],
    data = ["profiles.tsv"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "auth",
    srcs = ["cloud-bootstrap.sh"],
    args = ["auth"],
    data = ["profiles.tsv"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "whoami",
    srcs = ["cloud-bootstrap.sh"],
    args = ["whoami"],
    data = ["profiles.tsv"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "profiles",
    srcs = ["cloud-bootstrap.sh"],
    args = ["profiles"],
    data = ["profiles.tsv"],
    visibility = ["//visibility:public"],
)

# `bazel run //tools/cloud-bootstrap:configure-tailscale [-- --check | --file <path>]`
# writes .claude/tailscale-up.sh (Headscale login server, --accept-routes=true).
rust_library(
    name = "configure_tailscale_lib",
    srcs = ["src/configure_tailscale/lib.rs"],
    crate_name = "configure_tailscale",
    crate_root = "src/configure_tailscale/lib.rs",
    edition = "2021",
)

rust_binary(
    name = "configure-tailscale",
    srcs = ["src/configure_tailscale/main.rs"],
    edition = "2021",
    visibility = ["//visibility:public"],
    deps = [":configure_tailscale_lib"],
)

# Hermetic: --check and the CLI's error paths, plus the written hook AND the
# checked-in .claude/tailscale-up.sh executed against fake tailscale/tailscaled/
# sudo. Fails when the checked-in hook drifts from what the tool writes.
rust_test(
    name = "configure-tailscale_test",
    size = "small",
    srcs = ["src/configure_tailscale/tests.rs"],
    data = [
        ":configure-tailscale",
        "//:.claude/tailscale-up.sh",
    ],
    edition = "2021",
    env = {
        "BIN": "$(rootpath :configure-tailscale)",
        "HOOK_FILE": "$(rootpath //:.claude/tailscale-up.sh)",
    },
)

# Hermetic guard for the properties whose failure would be a PRIVILEGE ESCALATION
# or a SECRET LEAK -- not for the installers, which are network downloads whose
# only interesting property is "did curl work". It drives the real script's auth
# path against a fake `gcloud` that records argv, and pins: an unset/unknown
# profile bootstraps nothing (no implicit privileged default); a key whose
# client_email is not the profile's declared account is REFUSED and, crucially,
# fails CLOSED so no secret is read with it; the key travels as a --key-file path
# and never as argv bytes; every secret read is account+project pinned; values
# never reach stdout/stderr and land only in a 0600 file outside the workspace;
# gcloud's exit-0-with-ERROR auth failure is still a failure; an env var already
# set on the environment wins; and a placeholder ambient GCP token is cleared so
# the //tools/pulumi wrapper still applies its gcp-identities.tsv pin. For the
# build cache it pins the same two classes: the BuildBuddy key never reaching
# argv, and a profile that does not declare it never getting the cache
# configured -- plus the guards against a config that only looks enabled.
sh_test(
    name = "cloud-bootstrap_test",
    size = "small",
    srcs = ["cloud-bootstrap_test.sh"],
    data = [
        "cloud-bootstrap.sh",
        "profiles.tsv",
    ],
)

alias(
    name = "cloud_bootstrap_test",
    actual = ":cloud-bootstrap_test",
    deprecation = "Target :cloud_bootstrap_test is deprecated. Use :cloud-bootstrap_test instead. Will be removed in Phase 5.",
)
