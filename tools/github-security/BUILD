"""GitHub repository security settings that repo_config/Pulumi cannot express.

`infrastructure/pulumi/platform/repo_config` is the authority for repo governance
and owns everything it CAN own (secret scanning, push protection, Dependabot
security updates, the merge-queue ruleset). This package exists only for the
narrow set the pinned provider cannot reach.

  bazel run //tools/github-security:enable-dependency-graph   # prerequisite for dependency-review

Dependency graph is the worked example: pulumi-github v6.14.0 exposes it on the
ORGANIZATION resource only, never per repository, and
PATCH /repos/{owner}/{repo} silently ignores a
security_and_analysis[dependency_graph] field. The only working path is an
org-level code security configuration attached to the repo — which the target
does surgically, leaving every other setting `not_set` so it can never fight
Pulumi. The target is idempotent and prompts for the admin:org scope it needs
rather than telling the operator to go and get it.
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

exports_files(["enable-dependency-graph.sh"])

sh_binary(
    name = "enable-dependency-graph",
    srcs = ["enable-dependency-graph.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "enable-dependency-graph_test",
    size = "small",
    srcs = ["enable-dependency-graph_test.sh"],
    data = ["enable-dependency-graph.sh"],
)
