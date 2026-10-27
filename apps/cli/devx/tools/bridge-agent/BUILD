load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# gazelle:ignore

package(default_visibility = ["//apps/cli/devx:__subpackages__"])

rust_library(
    name = "bridge_agent_lib",
    srcs = ["src/lib.rs"],
    crate_name = "bridge_agent_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:private"],
    deps = ["@crates//:serde_json"],
)

rust_binary(
    name = "bridge-agent",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/cli/devx:__subpackages__"],
    deps = [":bridge_agent_lib"],
)

alias(
    name = "bridge_agent",
    actual = ":bridge-agent",
    visibility = ["//apps/cli/devx:__subpackages__"],
)

alias(
    name = "agent",
    actual = ":bridge-agent",
    visibility = ["//apps/cli/devx:__subpackages__"],
)

rust_test(
    name = "bridge-agent_test",
    size = "small",
    crate = ":bridge_agent_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

alias(
    name = "bridge_agent_test",
    actual = ":bridge-agent_test",
)
