"""vitruvian-roborock: local daemon, CLI (rrctl) and MCP server for Roborock vacuums."""

# Hand-written, and gazelle is kept out of the source trees below. The shipped
# artifact is a wheel that hatchling builds from pyproject.toml's src/ layout, so
# one library spanning src/ mirrors what users install; gazelle would instead
# emit a target per directory.
# gazelle:ignore
# gazelle:exclude src
# gazelle:exclude tests
# gazelle:exclude plugin
# gazelle:exclude rust_src

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_library")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//tools/pytest:defs.bzl", "py_test")

package(default_visibility = ["//apps/mcp/roborock:__subpackages__"])

py_library(
    name = "vitruvian_roborock",
    srcs = glob(["src/vitruvian_roborock/**/*.py"]),
    # Loaded with importlib.resources by both the daemon and the MCP server.
    data = ["src/vitruvian_roborock/dashboard/dashboard.html"],
    imports = ["src"],
    deps = [
        "@pip//aiohttp",
        "@pip//mcp",
        "@pip//python_roborock",
    ],
)

# `bazel run //apps/mcp/roborock:rrctl -- status`
py_binary(
    name = "rrctl",
    srcs = ["src/vitruvian_roborock/__main__.py"],
    imports = ["src"],
    main = "src/vitruvian_roborock/__main__.py",
    deps = [":vitruvian_roborock"],
)

# One target for the suite: the tests share conftest.py, and every one of them
# runs against fakes or a loopback server on an ephemeral port, never the cloud.
# Not named "tests": the launcher would shadow the tests/ directory in runfiles.
py_test(
    name = "roborock_test",
    size = "small",
    srcs = glob(["tests/*.py"]),
    imports = ["tests"],
    deps = [
        ":vitruvian_roborock",
        "@pip//aiohttp",
        "@pip//mcp",
        "@pip//python_roborock",
    ],
)

# The plugin manifests, for anything that packages or validates them.
filegroup(
    name = "plugin",
    srcs = glob(
        ["plugin/**"],
        exclude_directories = 1,
    ),
)

# --- Rust ports ---------------------------------------------------------------

rust_library(
    name = "roborock_rs_lib",
    srcs = glob(
        ["rust_src/*.rs"],
        exclude = ["rust_src/main.rs"],
    ),
    compile_data = ["src/vitruvian_roborock/dashboard/dashboard.html"],
    crate_root = "rust_src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [
        "@crates//:serde",
        "@crates//:serde_json",
    ],
)

rust_binary(
    name = "rrctl-rs",
    srcs = ["rust_src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":roborock_rs_lib"],
)

alias(
    name = "rrctl_rs",
    actual = ":rrctl-rs",
)

rust_test(
    name = "roborock_rs_test",
    size = "small",
    crate = ":roborock_rs_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)
