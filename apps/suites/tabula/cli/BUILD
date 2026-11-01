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

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# tabcli: Tabula operations CLI (auth, workos, db, config, init, version).
# Dev-loop and infra commands were retired in the monorepo migration: code
# checks run via `bazel test //tabula/...`, deploys via the
# //tabula/infra/app project.
# gazelle:ignore
# gazelle:exclude rs

# Inter-app boundary (#82): default targets to tabula-internal visibility so
# other top-level apps can't depend on tabula internals. Explicit per-target
# visibility (public artifacts + the extension->api //tabula:__subpackages__
# deps) is preserved below.
package(default_visibility = ["//apps/suites/tabula:__subpackages__"])

test_suite(
    name = "unit_tests",
    tests = [":tabcli_test"],
)

rust_library(
    name = "tabcli_lib",
    srcs = glob(
        ["rs/src/**/*.rs"],
        exclude = ["rs/src/main.rs"],
    ),
    crate_name = "tabcli_lib",
    crate_root = "rs/src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "tabcli",
    srcs = ["rs/src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":tabcli_lib"],
)

rust_test(
    name = "tabcli_test",
    size = "small",
    crate = ":tabcli_lib",
    data = [
        ".release-please-manifest.json",
        "package.json",
        "release-please-config.json",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

pipeline_unit(
    name = "tabula-cli",
    depends_on = ["tabula-shared"],
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":unit_tests",
        ":tabcli_test",
    ],
    tier = "L1",
    timeout_minutes = 15,
)
