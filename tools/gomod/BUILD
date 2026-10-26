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

# gazelle:ignore

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

rust_library(
    name = "gomod_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    compile_data = ["tidy.sh"],
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "tidy",
    srcs = ["src/main.rs"],
    data = ["//tools/ci:transient-lib.sh"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":gomod_lib"],
)

# Same engine, --check baked in: read-only by construction (`go mod tidy -diff`
# never writes), so it is safe as a required presubmit gate.
rust_binary(
    name = "check",
    srcs = ["src/main.rs"],
    args = ["--check"],
    data = ["//tools/ci:transient-lib.sh"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":gomod_lib"],
)

alias(
    name = "tidy-rs",
    actual = ":tidy",
    visibility = ["//visibility:public"],
)

alias(
    name = "tidy_rs",
    actual = ":tidy",
    visibility = ["//visibility:public"],
)

alias(
    name = "check-rs",
    actual = ":check",
    visibility = ["//visibility:public"],
)

alias(
    name = "check_rs",
    actual = ":check",
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "tidy-sh",
    srcs = ["tidy.sh"],
    # tidy.sh sources the shared transport-failure classifier so it can tell
    # "your modules drifted" from "the module proxy fell over".
    data = ["//tools/ci:transient-lib.sh"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "check-sh",
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

sh_test(
    name = "tidy-rs_test",
    size = "small",
    srcs = ["tidy_test.sh"],
    args = ["$(rootpath :tidy)"],
    data = [
        "tidy.sh",
        ":tidy",
        "//tools/ci:transient-lib.sh",
    ],
    env = {
        "UNDER_TEST": "$(rootpath :tidy)",
    },
)

rust_test(
    name = "gomod_lib_test",
    size = "small",
    crate = ":gomod_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

sh_test(
    name = "tidy-rs-parity_test",
    size = "medium",
    srcs = ["tidy-rs-parity_test.sh"],
    data = [
        "tidy.sh",
        ":check",
        ":tidy",
        "//tools/ci:transient-lib.sh",
    ],
    env = {
        "CHECK_RS": "$(rootpath :check)",
        "TIDY_RS": "$(rootpath :tidy)",
        "TIDY_SH": "$(rootpath tidy.sh)",
    },
)
