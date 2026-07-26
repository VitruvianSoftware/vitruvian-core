"""
Build supporting tools.

The tools subpackage is used to define build rules and configurations for tools
used throughout the repository. Firstparty tools not required for build support
should live elsewhere.

Of special note is that we're using the `bazel_env.bzl` tool to re-export tools
used under Bazel as a `bin/` tree which can be added to the `$PATH`. The
included `.envrc` automates this for you.

"""

load("@bazel_env.bzl", "bazel_env")
load("@bazelrc-preset.bzl", "bazelrc_preset")
load("@gazelle//:go_tools.bzl", "GO_TOOLS")
load("@multitool//:tools.bzl", MULTITOOL_TOOLS = "TOOLS")
load("@npm//:defs.bzl", "npm_link_all_packages")
load("@npm//tools:yo/package_json.bzl", yo_bin = "bin")
load("@rules_python//python/entry_points:py_console_script_binary.bzl", "py_console_script_binary")

package(default_visibility = ["//visibility:public"])

bazelrc_preset(
    name = "preset",
    doc_link_template = "https://registry.build/flag/bazel?filter={flag}",
)

py_console_script_binary(
    name = "copier",
    pkg = "@pip//copier",
)

npm_link_all_packages(name = "node_modules")

yo_bin.yo_binary(name = "yo")

bazel_env(
    name = "bazel_env",
    toolchains = {
        "jdk": "@rules_java//toolchains:current_host_java_runtime",
        "python": "@rules_python//python:current_py_toolchain",
        # NB: uv is deliberately NOT here. `toolchains` entries become a
        # genrule's `toolchains` attribute, which demands TemplateVariableInfo
        # or ToolchainTypeInfo; `@multitool//tools/uv:uv` is a plain `tool`
        # rule and provides neither, so listing it made
        # //tools:bazel_env.helper_genrule.uv fail analysis. That target is
        # `manual`-tagged, so `bazel build //...` never saw it -- but
        # target-determinator's `cquery deps(//...)` does, which killed the
        # affected-targets fast path on every CI run (full //... sweep instead).
        # uv is still on $PATH: MULTITOOL_TOOLS below already maps it.
        # prettier moved to `tools` for the same reason -- it is a js_binary.
        "nodejs": "@nodejs_toolchains//:resolved_toolchain",
    },
    tools = {
        # Mapping from tool binary name ($PATH entry) to Bazel label
        "buildifier": "@buildifier_prebuilt//:buildifier",
        "prettier": "//tools/format:prettier",
        "format": "//tools/format:format",
        "cargo": "@rules_rust//tools/upstream_wrapper:cargo",
        "copier": ":copier",
        "go": "@rules_go//go",
        "jar": "$(JAVABASE)/bin/jar",
        "java": "$(JAVA)",
        "node": "$(NODE_PATH)",
        "npm": "$(NPM_PATH)",
        "pnpm": "@pnpm",
        "yo": ":yo",
        "python": "$(PYTHON3)",
        "bundle": "@ruby//:bundle",
        "gem": "@ruby//:gem",
        "ruby": "@ruby",
    } | MULTITOOL_TOOLS | GO_TOOLS,
)
