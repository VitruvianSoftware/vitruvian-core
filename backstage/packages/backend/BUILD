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
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# Inter-app boundary (#82): default targets to backstage-internal visibility.
package(default_visibility = ["//backstage:__subpackages__"])

# Minimal packaging target so aspect_rules_js can link this pnpm workspace
# package into the virtual store.
npm_package(
    name = "pkg",
    srcs = ["package.json"] + glob(
        [
            "src/**",
            "tsconfig.json",
        ],
        allow_empty = True,
    ),
    visibility = ["//visibility:public"],
)

pipeline_unit(
    name = "backstage-backend",
    persona = "backend",
    runner = "ubuntu-latest",
    test_targets = [":pkg"],
    tier = "L1",
    timeout_minutes = 20,
)
