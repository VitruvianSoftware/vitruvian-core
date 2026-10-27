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

exports_files([
    "catalog.schema.json",
    "public-key.txt",
    "sources.json",
    "tools.json",
])

rust_library(
    name = "catalog_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/bin/**"],
    ),
    crate_name = "catalog",
    edition = "2021",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "catalog_lib_test",
    size = "small",
    compile_data = [
        "public-key.txt",
        "testdata/Info.plist",
    ],
    crate = ":catalog_lib",
    data = [
        "catalog.schema.json",
        "public-key.txt",
        "sources.json",
        "tools.json",
        "//:workflow_files",
        "//apps/desktop/vitruvian:Resources/Info.plist",
        "//apps/desktop/vitruvian:Sources/Vitruvian/Services/Platform/External/Catalogue/CatalogueSigning.swift",
    ] + glob(["testdata/**"]),
)

rust_binary(
    name = "sign",
    srcs = ["src/bin/sign.rs"],
    data = [
        "catalog.schema.json",
        "public-key.txt",
        "tools.json",
    ],
    edition = "2021",
    visibility = ["//visibility:public"],
    deps = [":catalog_lib"],
)

rust_binary(
    name = "check-downloads",
    srcs = ["src/bin/check_downloads.rs"],
    edition = "2021",
    visibility = ["//visibility:public"],
    deps = [":catalog_lib"],
)

rust_binary(
    name = "rehearse",
    srcs = ["src/bin/rehearse.rs"],
    edition = "2021",
    visibility = ["//visibility:public"],
    deps = [":catalog_lib"],
)

rust_binary(
    name = "bump",
    srcs = ["src/bin/bump.rs"],
    data = [
        "catalog.schema.json",
        "sources.json",
        "tools.json",
        "//apps/desktop/vitruvian:Resources/Info.plist",
    ],
    edition = "2021",
    visibility = ["//visibility:public"],
    deps = [":catalog_lib"],
)

test_suite(
    name = "catalog_test",
    tests = [":catalog_lib_test"],
)

test_suite(
    name = "signing_test",
    tests = [":catalog_lib_test"],
)

test_suite(
    name = "check_downloads_test",
    tests = [":catalog_lib_test"],
)

test_suite(
    name = "rehearse_test",
    tests = [":catalog_lib_test"],
)

test_suite(
    name = "bump_test",
    tests = [":catalog_lib_test"],
)

test_suite(
    name = "release_trigger_test",
    tests = [":catalog_lib_test"],
)
