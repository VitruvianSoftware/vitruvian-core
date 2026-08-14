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

load("@aspect_rules_js//npm:defs.bzl", "npm_package")
load("@aspect_rules_swc//swc:defs.bzl", "swc")
load("@aspect_rules_ts//ts:defs.bzl", "ts_project")
load("@bazel_skylib//lib:partial.bzl", "partial")

# @tabula/shared: types + utilities consumed by //tabula/extension and
# //tabula/web as a pnpm workspace package (main: dist/index.js).
# Hand-authored for the same reason as //mcp-slack.
# gazelle:ignore
# gazelle:exclude src

# Inter-app boundary (#82): default targets to tabula-internal visibility so
# other top-level apps can't depend on tabula internals. Explicit per-target
# visibility (public artifacts + the extension->api //tabula:__subpackages__
# deps) is preserved below.
package(default_visibility = ["//tabula:__subpackages__"])

ts_project(
    name = "lib",
    srcs = glob(["src/**/*.ts"]),
    declaration = True,
    declaration_map = True,
    out_dir = "dist",
    resolve_json_module = True,
    root_dir = "src",
    source_map = True,
    # Bare `swc` does not inherit this target's own out_dir/root_dir (custom
    # transpilers aren't passed them -- see packages/design-system/BUILD for
    # the full explanation), so SWC would otherwise land real JS output
    # mirroring root_dir in place instead of under dist/, alongside only the
    # tsc-emitted declarations. Currently latent here (only type-only imports
    # of @tabula/shared get bundled today), but identical to a break that
    # surfaced for real in @vitruviansoftware/design-system.
    transpiler = partial.make(
        swc,
        out_dir = "dist",
        root_dir = "src",
    ),
    tsconfig = "tsconfig.json",
)

# Linked into consumers' node_modules by npm_translate_lock (pnpm workspace
# package); rules_js 3.x expects the target to be named "pkg".
#
# PUBLIC on purpose (allowlisted in tools/conformance/public-targets.tsv): the
# rules_js virtual store is rooted at the repo-root package (//:node_modules,
# npm_link_all_packages in //:BUILD), so GENERATED store link targets for this
# workspace package dep on :pkg from OUTSIDE //tabula. App-internal visibility
# would break that generated edge at analysis time.
npm_package(
    name = "pkg",
    srcs = [
        "package.json",
        ":lib",
    ],
    visibility = ["//visibility:public"],
)
