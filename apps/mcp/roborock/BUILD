"""vitruvian-roborock: local daemon, CLI (rrctl) and MCP server for Roborock vacuums."""

# Hand-written, and gazelle is kept out of the source trees below. The shipped
# artifact is a wheel that hatchling builds from pyproject.toml's src/ layout, so
# one library spanning src/ mirrors what users install; gazelle would instead
# emit a target per directory.
# gazelle:ignore
# gazelle:exclude src
# gazelle:exclude tests
# gazelle:exclude plugin

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_library")
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
