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

# gazelle:ignore

load("@aspect_rules_js//js:defs.bzl", "js_test")
load("@npm//:defs.bzl", "npm_link_all_packages")
load("@npm//apps/web/gods-eye-view:vite/package_json.bzl", vite = "bin")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//tools/doctor:defs.bzl", "doctor")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

package(default_visibility = ["//visibility:public"])

npm_link_all_packages(name = "node_modules")

vite.vite(
    name = "build",
    srcs = glob([
        "src/**",
        "public/**",
        "config/**",
    ]) + [
        "index.html",
        "package.json",
        "style.css",
        "vite.config.js",
        ":node_modules",
    ],
    args = ["build"],
    chdir = package_name(),
    out_dirs = ["dist"],
)

js_test(
    name = "unit_tests",
    chdir = package_name(),
    data = glob([
        "src/**",
        "scripts/**",
        "public/**",
        "config/**",
        "docs/**",
        "pinokio/**",
        "tools/**",
    ]) + glob(
        ["*"],
        exclude = ["BUILD"],
    ) + [
        ":node_modules",
    ],
    entry_point = "scripts/run-unit-tests.mjs",
)

sh_test(
    name = "cesium_assets_test",
    size = "small",
    srcs = ["scripts/verify-cesium-assets.sh"],
    data = [":build"],
)

doctor(
    name = "doctor",
    label = "gods-eye-view",
    required = [
        "bazel",
        "node",
        "pnpm",
        "git",
    ],
)

pipeline_unit(
    name = "gods-eye-view",
    persona = "frontend",
    runner = "ubuntu-latest",
    test_targets = [
        ":unit_tests",
        ":cesium_assets_test",
        ":build",
    ],
    tier = "L1",
    timeout_minutes = 15,
)
