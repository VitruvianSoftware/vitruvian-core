"""The API half of standing up a per-agent GitHub App identity.

  bazel run //tools/agent-app -- convert <manifest-code> <out.pem>
  bazel run //tools/agent-app -- installations <app-id> <key.pem>
  bazel run //tools/agent-app -- repos <app-id> <key.pem> <installation-id>
  bazel run //tools/agent-app -- token <app-id> <key.pem> <installation-id>

Every agent pushes and merges as one human account, so PR authorship is not
attribution and no agent can approve another's work -- GitHub blocks
self-approval and every PR is self-authored from its point of view. The fix is
one GitHub App per agent; see docs/guides/agent-github-identities.md.

App CREATION is the one part that cannot live here. GitHub's Apps REST API has
fourteen endpoints and none of them creates an App: the only path is the
App-manifest flow, whose final step IS an API call (`convert`, below) but whose
`code` exists only after a signed-in human approves the handshake in a browser.
So the manual part is two clicks per agent and everything either side of them is
a target here -- which is the point, because these are the steps someone will
otherwise do by hand at 1am and mis-remember afterwards.

The runbook these implement is docs/guides/creating-an-agent-github-app.md.
"""

# Hand-written: gazelle's Python extension would otherwise generate its own
# targets for permission_drift.py beside these.
# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["agent-app.sh"])

sh_binary(
    name = "agent-app",
    srcs = ["agent-app.sh"],
    data = [
        "agents.tsv",
        "permissions.tsv",
        "workflow-allowlist.txt",
        # branch-delete's gate.
        "//tools/landed:landed.sh",
    ],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "agent-app_test",
    size = "small",
    srcs = ["agent-app_test.sh"],
    data = [
        "agent-app.sh",
        "agents.tsv",
        "permissions.tsv",
        "workflow-allowlist.txt",
        # branch-delete's gate: run for real once, to prove a test-only
        # override of it is ignored outside bazel test.
        "//tools/landed:landed.sh",
        # pr-hold's label must be the one these gates treat as a person's hold.
        "//tools/ci:release-beta-gate.sh",
        "//tools/ci:release-hold.sh",
        # The script's --jq filters run for real, on responses saved from
        # GitHub; the remote-exec image has no jq, so bring our own.
        "@jq_toolchains//:resolved_toolchain",
    ] + glob(["testdata/*.json"]),
    env = {"JQ_BIN": "$(JQ_BIN)"},
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
)

alias(
    name = "agent_app_test",
    actual = ":agent-app_test",
    deprecation = "Target :agent_app_test is deprecated. Use :agent-app_test instead. Will be removed in Phase 5.",
)

# Does each agent App have exactly the permissions permissions.tsv declares?
# Reads GitHub as your gh login (GH_TOKEN wins if set). Needs the network, so it
# is a command and a daily workflow (agent-app-permissions.yaml), not a test.
py_binary(
    name = "permission-drift",
    srcs = ["permission_drift.py"],
    data = [
        "agents.tsv",
        "permissions.tsv",
    ],
    imports = ["."],
    main = "permission_drift.py",
)

# The judging, with a fake GitHub and a local HTTP server: no real network.
py_test(
    name = "permission_drift_test",
    size = "small",
    srcs = [
        "permission_drift.py",
        "permission_drift_test.py",
    ],
    data = [
        "agents.tsv",
        "permissions.tsv",
    ],
    # The folder name has a hyphen, so it cannot be a package: import by path.
    imports = ["."],
    main = "permission_drift_test.py",
)
