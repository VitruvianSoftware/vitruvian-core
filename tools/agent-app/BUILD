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

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["agent-app.sh"])

sh_binary(
    name = "agent-app",
    srcs = ["agent-app.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "agent_app_test",
    size = "small",
    srcs = ["agent-app_test.sh"],
    data = ["agent-app.sh"],
)
