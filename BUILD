"""Targets in the repository root"""

load("@aspect_rules_js//js:defs.bzl", "js_library")
load("@gazelle//:def.bzl", "gazelle")
load("@npm//:defs.bzl", "npm_link_all_packages")
load("@pip//:requirements.bzl", "all_whl_requirements")
load("@rules_multirun//:defs.bzl", "multirun")
load("@rules_python_gazelle_plugin//manifest:defs.bzl", "gazelle_python_manifest")
load("@rules_python_gazelle_plugin//modules_mapping:def.bzl", "modules_mapping")
load("//tools/doctor:defs.bzl", "doctor")

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
        "ktlint-baseline.xml",
        ".editorconfig",
        "pmd.xml",
        ".shellcheckrc",
        ".clippy.toml",
    ],
    visibility = ["//:__subpackages__"],
)

# .github/ has no BUILD file, so its workflows belong to THIS package and must
# be exported to be reachable as a `data` dep.
#
# //tools/delivery/gen's parity test compares the GENERATED delivery workflow
# against the LEGACY one it took the development lane from, mechanically, on
# every test run — the anti-transcription-drift guard for the delivery
# orchestrator's Phase 1 (spec §6). Reading a frozen copy instead would let the
# two real files drift apart while the test stayed green, which is the exact
# failure the guard exists to catch. Narrow visibility: this is not an
# invitation for other targets to depend on workflow files.
#
# Both entries go away with Phase 3, which deletes the legacy workflow.
exports_files(
    [
        ".github/workflows/_deploy-cloud-run.yaml",
        ".github/workflows/delivery.yaml",
        ".github/workflows/oauth-user-inspector-deploy.yaml",
    ],
    visibility = ["//tools/delivery/gen:__pkg__"],
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
# tools/pulumi holds a hand-authored macro (defs.bzl) + wrapper scripts; gazelle
# would otherwise generate a bzl_library with an unresolvable rules_shell dep.
# gazelle:exclude tools/pulumi
# tools/gitops is the same: a hand-authored macro (defs.bzl) + wrapper script
# loading rules_shell; exclude it for the identical bzl_library dep reason.
# gazelle:exclude tools/gitops
# tools/doctor is the same: a hand-authored macro (defs.bzl) + the doctor.sh
# engine loading rules_shell; exclude it for the identical bzl_library dep reason.
# gazelle:exclude tools/doctor
# tabula is a JS/TS app suite with hand-authored BUILD files (ts_project +
# webpack/next js_run_binary + jest/itest wiring) that the JS gazelle extension
# would mangle, same situation as mcp-slack. Keep gazelle out of the subtree.
# gazelle:exclude tabula
# pulumi/library is a grafted external library (Apache-2.0) with a multi-module
# Go tree (own go.mod per component) and a pnpm-workspace TS tree. Its Go BUILD
# files are hand-authored; its TS packages are built/tested natively (vitest)
# with Bazel ts_project targets deferred to a follow-up. Keep gazelle out so it
# does not fight the hand-authored/absent BUILD files.
# gazelle:exclude pulumi/library
# pulumi/examples holds the reference foundation stages — standalone Pulumi
# projects (own go.mod, resolving the in-tree library via replace directives,
# not in //:go.work) wrapped by hand-authored pulumi_project BUILD files, same
# as infrastructure/pulumi. Keep gazelle out of the subtree.
# gazelle:exclude pulumi/examples

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

# One-command BUILD/source hygiene: regenerate BUILD files (gazelle), refresh the
# Python deps manifest, then format everything (//tools/format = buildifier + every
# per-language formatter). Sequential so the formatter sees gazelle's freshly
# written BUILD files. Run `bazel run //:tidy`; the Tidy Check CI job fails a PR
# when running this would change anything.
multirun(
    name = "tidy",
    commands = [
        ":gazelle",
        ":gazelle_python_manifest.update",
        "//tools/format",
    ],
    jobs = 1,  # sequential: gazelle writes BUILD files, then format formats them
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

# Core developer-environment overview: `bazel run //:doctor`. Only bazel + git
# are hard-required so this never fails on a partial setup — everything else is
# informational (warns, never gates). Per-app `:doctor` targets tighten the
# required set for their own toolchain.
doctor(
    name = "doctor",
    label = "vitruvian-core (core toolchain)",
    optional = [
        "node",
        "pnpm",
        "go",
        "gh",
        "gcloud",
        "docker",
        "direnv",
    ],
    required = [
        "bazel",
        "git",
    ],
)
