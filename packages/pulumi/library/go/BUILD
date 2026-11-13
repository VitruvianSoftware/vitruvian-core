# gazelle:prefix github.com/VitruvianSoftware/pulumi-library/go

load("@rules_shell//shell:sh_test.bzl", "sh_test")

sh_test(
    name = "agent_docs_test",
    size = "small",
    srcs = ["//tools/conformance:skill_docs_check.sh"],
    args = [
        "--root",
        "packages/pulumi/library",
        "packages/pulumi/library/.agents/skills/pulumi-library-ci/SKILL.md",
    ],
    data = [
        "//:packages/pulumi/library/.agents/skills/pulumi-library-ci/SKILL.md",
        "//:packages/pulumi/library/.github/workflows/release.yml",
        "//packages/pulumi/library/go/internal/testutil:docs_files",
        "//packages/pulumi/library/go/pkg/cai_monitoring:docs_files",
        "//packages/pulumi/library/go/pkg/centralized_logging:docs_files",
        "//packages/pulumi/library/go/pkg/cicd:docs_files",
        "//packages/pulumi/library/go/pkg/cloud_storage:docs_files",
        "//packages/pulumi/library/go/pkg/iam:docs_files",
        "//packages/pulumi/library/go/pkg/network:docs_files",
        "//packages/pulumi/library/ts:docs_files",
        "//packages/pulumi/library/ts/packages/app:docs_files",
    ],
)
