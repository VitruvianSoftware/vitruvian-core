# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# @vitruviansoftware/design-system: Vitruvian, the shared design language --
# CSS token layer + React component library + Storybook.
#
# This BUILD is hand-authored for the same reason as //mcp-slack and
# //tabula/shared: a single co-located ts_project whose tsconfig (rootDir
# ./src, outDir ./dist) resolves consistently, plus a Storybook devserver the
# aspect JS/TS Gazelle extension does not model. Gazelle would rewrite this
# file (leaving a broken empty src glob), emit a separate src/BUILD, and try to
# generate targets for the .storybook/ config.
# gazelle:ignore
# gazelle:exclude src
# gazelle:exclude .storybook

load("@aspect_rules_js//js:defs.bzl", "js_binary")
load("@aspect_rules_js//npm:defs.bzl", "npm_package")
load("@aspect_rules_swc//swc:defs.bzl", "swc")
load("@aspect_rules_ts//ts:defs.bzl", "ts_project")
load("@npm//:defs.bzl", "npm_link_all_packages")
load("//tools/doctor:defs.bzl", "doctor")

# Unlike the per-app packages, the design system is platform-level: every app
# is meant to depend on it, so the inter-app boundary (#82) does not apply --
# //packages is outside the app firewall the conformance check patrols
# (check_app_visibility scans the app roots only), so no allowlist row in
# tools/conformance/public-targets.tsv is needed or accepted here.
package(default_visibility = ["//visibility:public"])

npm_link_all_packages(name = "node_modules")

# Stories are dev-only: they must not land in dist/ or in the published
# package, so they are excluded from the library and type-checked by Storybook
# itself rather than by this target.
ts_project(
    name = "lib",
    srcs = glob(
        [
            "src/**/*.ts",
            "src/**/*.tsx",
        ],
        exclude = ["src/**/*.stories.tsx"],
    ),
    declaration = True,
    declaration_map = True,
    out_dir = "dist",
    resolve_json_module = True,
    root_dir = "src",
    source_map = True,
    transpiler = swc,
    tsconfig = "tsconfig.json",
    deps = [
        ":node_modules/@types/react",
        ":node_modules/@types/react-dom",
        ":node_modules/react",
    ],
)

# Linked into consumers' node_modules by npm_translate_lock (pnpm workspace
# package); rules_js 3.x expects the target to be named "pkg".
#
# The stylesheets are shipped from src/ -- they are not compiled, and the
# package's exports map points at src/*.css. dist/ holds only the JS + .d.ts.
npm_package(
    name = "pkg",
    srcs = [
        "package.json",
        "src/tokens.css",
        "src/vitruvian.css",
        ":lib",
    ],
    visibility = ["//visibility:public"],
)

# The Storybook devserver: `bazel run //packages/design-system:storybook`.
# Not a build target -- Storybook is a dev tool, and its vite pipeline is not
# modelled in Bazel. The static export (`build-storybook`) is deliberately left
# to pnpm until someone needs it in CI; see the note in README.md.
js_binary(
    name = "storybook",
    args = [
        "dev",
        "-p",
        "6006",
        "--no-open",
    ],
    data = [
        "package.json",
        "tsconfig.json",
        ":node_modules/@storybook/addon-a11y",
        ":node_modules/@storybook/addon-docs",
        ":node_modules/@storybook/react-vite",
        ":node_modules/@tailwindcss/vite",
        ":node_modules/react",
        ":node_modules/react-dom",
        ":node_modules/storybook",
        ":node_modules/tailwindcss",
        ":node_modules/vite",
    ] + glob([
        ".storybook/**",
        "src/**",
    ]),
    entry_point = ":node_modules/storybook/dir",
)

# Developer-environment check: `bazel run //packages/design-system:doctor`.
doctor(
    name = "doctor",
    label = "design-system (Vitruvian)",
    required = [
        "bazel",
        "git",
        "node",
        "pnpm",
    ],
)
