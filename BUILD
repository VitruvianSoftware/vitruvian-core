"""Targets in the repository root"""

load("@aspect_rules_js//js:defs.bzl", "js_library")
load("@gazelle//:def.bzl", "gazelle")
load("@npm//:defs.bzl", "npm_link_all_packages")
load("@pip//:requirements.bzl", "all_whl_requirements")
load("@rules_python_gazelle_plugin//manifest:defs.bzl", "gazelle_python_manifest")
load("@rules_python_gazelle_plugin//modules_mapping:def.bzl", "modules_mapping")

# TODO: remove once https://github.com/aspect-build/aspect-cli/issues/560 done
# gazelle:js_npm_package_target_name pkg
npm_link_all_packages(name = "node_modules")

js_library(
    name = "eslintrc",
    srcs = ["eslint.config.mjs"],
    visibility = ["//:__subpackages__"],
    deps = [
        ":node_modules/@eslint/js",
        ":node_modules/typescript-eslint",
    ],
)

js_library(
    name = "prettier_config",
    srcs = ["prettier.config.cjs"],
    visibility = ["//tools/format:__pkg__"],
    deps = [],
)

js_library(
    name = "prettier_ignore",
    srcs = [".prettierignore"],
    visibility = ["//tools/format:__pkg__"],
    deps = [],
)

exports_files(
    [
        ".clang-tidy",
        ".rubocop.yml",
        "ktlint-baseline.xml",
        ".editorconfig",
        "pmd.xml",
        ".shellcheckrc",
        ".clippy.toml",
    ],
    visibility = ["//:__subpackages__"],
)

# gazelle:prefix github.com/VitruvianSoftware/vitruvian-core

# It's faster to avoid type-checking in a devserver when using monorepo packages.
# If you commonly ship your npm packages outside the repo, change this to "npm_package"
# gazelle:js_package_rule_kind js_library

# We prefer BUILD instead of BUILD.bazel
# gazelle:build_file_name BUILD
# gazelle:exclude githooks/*
# infrastructure/pulumi is a separate Go module (not in //:go.work), deployed
# via `pulumi up` and never Bazel-built. Keep gazelle out of it entirely.
# gazelle:exclude infrastructure

gazelle(
    name = "gazelle",
    env = {
        "ENABLE_LANGUAGES": ",".join([
            "starlark",
            "go",
            # NB: "kotlin" is intentionally omitted. The repo contains no Kotlin
            # sources, and the Kotlin Gazelle extension generates a
            # kt_jvm_library named after each package directory, which collides
            # with the existing go_library/go_binary/ts_project targets in the
            # grafted Go (homelab, devx) and TypeScript (mcp-slack) projects --
            # aborting `bazel run //:gazelle` repo-wide. Re-add it here if/when
            # actual Kotlin sources are introduced.
            "python",
            "js",
            "cc",
        ]),
    },
    gazelle = "@multitool//tools/gazelle",
)

exports_files(
    ["pyproject.toml"],
    visibility = ["//:__subpackages__"],
)

# Produce aspect_rules_py targets rather than rules_python
# gazelle:map_kind py_binary py_binary @aspect_rules_py//py:defs.bzl
# gazelle:map_kind py_library py_library @aspect_rules_py//py:defs.bzl
# gazelle:map_kind py_test py_test //tools/pytest:defs.bzl
#
# Don't walk into virtualenvs when looking for python sources.
# We don't intend to plant BUILD files there.
# gazelle:exclude **/*.venv
#
# Fetches metadata for python packages we depend on.
modules_mapping(
    name = "modules_map",
    wheels = all_whl_requirements,
)

# Provide a mapping from an import to the installed package that provides it.
# Needed to generate BUILD files for .py files.
# This macro produces two targets:
# - //:gazelle_python_manifest.update can be used with `bazel run`
#   to recalculate the manifest
# - //:gazelle_python_manifest.test is a test target ensuring that
#   the manifest doesn't need to be updated
gazelle_python_manifest(
    name = "gazelle_python_manifest",
    modules_mapping = ":modules_map",
    pip_repository_name = "pip",
)
