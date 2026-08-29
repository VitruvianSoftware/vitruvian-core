# Monorepo Naming Convention Linter & Test Harness.
# gazelle:ignore

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

sh_binary(
    name = "lint-naming",
    srcs = ["lint_naming.py"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "lint-naming_test",
    size = "small",
    srcs = ["test_runner.sh"],
    data = glob([
        "*.py",
        "rules/*.py",
        "tests/*.py",
        "testdata/**/*",
    ]),
    visibility = ["//visibility:public"],
)
