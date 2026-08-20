"""Keep the `replace`-coupled Go modules' pins in sync.

  bazel run //tools/gomod:tidy     # fix:  rewrite go.mod/go.sum in place
  bazel run //tools/gomod:check    # gate: report drift, change nothing

Every module under pulumi/examples/go-foundation consumes the library through a
`replace` to a local path while carrying its own copy of the library's
transitive pins. Dependabot tidies only the module it bumps and cannot see
across a `replace`, so a library bump silently desyncs the examples -- surfacing
in CI as the contextless "go: updates to go.mod needed". `:check` turns that
into a named module, a diff, and the command that fixes it. See
tools/gomod/tidy.sh for the full rationale.

Deliberately NOT a member of `//:tidy`, despite being a tidy step. `//:tidy` is
what `tidy-check` runs before asserting a clean tree, and it is a hermetic
BUILD-file/formatter pass. `go mod tidy` over 56 modules needs the module proxy,
so folding it in would put a network dependency inside a required check that
currently has none -- trading a precise, path-gated failure in example-build for
a flaky one in tidy-check. The gate lives next to the build it protects instead.
"""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

sh_binary(
    name = "tidy",
    srcs = ["tidy.sh"],
    # tidy.sh sources the shared transport-failure classifier so it can tell
    # "your modules drifted" from "the module proxy fell over".
    data = ["//tools/ci:transient-lib.sh"],
    visibility = ["//visibility:public"],
)

# Same engine, --check baked in: read-only by construction (`go mod tidy -diff`
# never writes), so it is safe as a required presubmit gate.
sh_binary(
    name = "check",
    srcs = ["tidy.sh"],
    args = ["--check"],
    data = ["//tools/ci:transient-lib.sh"],
    visibility = ["//visibility:public"],
)

sh_test(
    name = "tidy_test",
    size = "small",
    srcs = ["tidy_test.sh"],
    data = [
        "tidy.sh",
        "//tools/ci:transient-lib.sh",
    ],
)
