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

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

package(default_visibility = ["//packages/design-system-android:__subpackages__"])

# Emits VitruvianTokens.kt from //packages/design-system's tokens.json.
#
# `bazel run //packages/design-system-android/tools:gen_tokens -- \
#   --tokens packages/design-system/src/tokens.json \
#   --header packages/design-system-android/tools/kt_license_header.txt \
#   --out packages/design-system-android/src/main/kotlin/dev/vitruvian/design/VitruvianTokens.kt`
rust_binary(
    name = "gen_tokens",
    srcs = ["src/main.rs"],
    data = ["kt_license_header.txt"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":gen_tokens_lib"],
)

alias(
    name = "gen_tokens-rs",
    actual = ":gen_tokens",
    visibility = ["//visibility:public"],
)

alias(
    name = "gen_tokens_rs",
    actual = ":gen_tokens",
    visibility = ["//visibility:public"],
)

# It reads JSON with its own copy of CPython's scanner
# rather than serde_json, which accepts a different language (no NaN, a
# 128-deep limit, integers past 64 bits rounded) and words its errors
# differently; serde_json is the reference the unit tests check that
# scanner against. src/unicode_tables.rs carries the character classes
# Python 3.12's own character data uses.
rust_library(
    name = "gen_tokens_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = [
            "src/gen_unicode_tables.rs",
            "src/main.rs",
            "src/parity_test.rs",
            "src/tokens_are_current.rs",
        ],
    ),
    crate_name = "gen_tokens",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "gen-unicode-tables",
    srcs = ["src/gen_unicode_tables.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//visibility:public"],
    deps = [":gen_tokens_lib"],
)

alias(
    name = "gen_unicode_tables",
    actual = ":gen-unicode-tables",
    visibility = ["//visibility:public"],
)

# The #[cfg(test)] unit tests in src/.
rust_test(
    name = "gen_tokens_lib_test",
    size = "small",
    compile_data = ["//packages/design-system:src/tokens.json"],
    crate = ":gen_tokens_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = ["@crates//:serde_json"],
)

test_suite(
    name = "gen_tokens_test",
    tests = [":gen_tokens_lib_test"],
    visibility = ["//visibility:public"],
)

rust_binary(
    name = "parity_test_rs",
    srcs = ["src/parity_test.rs"],
    data = [
        "//packages/design-system:src/Icons.tsx",
        "//packages/design-system:src/Illustrations.tsx",
        "//packages/design-system-android:kotlin_sources",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_test(
    name = "parity_test_rs_test",
    size = "small",
    srcs = ["src/parity_test.rs"],
    data = [
        "//packages/design-system:src/Icons.tsx",
        "//packages/design-system:src/Illustrations.tsx",
        "//packages/design-system-android:kotlin_sources",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "tokens_are_current_rs",
    srcs = ["src/tokens_are_current.rs"],
    data = [
        "kt_license_header.txt",
        ":gen_tokens",
        "//packages/design-system:src/tokens.json",
        "//packages/design-system-android:src/main/kotlin/dev/vitruvian/design/VitruvianTokens.kt",
        "//tools/format:ktfmt",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":gen_tokens_lib"],
)

rust_test(
    name = "tokens_are_current_rs_test",
    size = "small",
    srcs = ["src/tokens_are_current.rs"],
    data = [
        "kt_license_header.txt",
        ":gen_tokens",
        "//packages/design-system:src/tokens.json",
        "//packages/design-system-android:src/main/kotlin/dev/vitruvian/design/VitruvianTokens.kt",
        "//tools/format:ktfmt",
    ],
    edition = "2021",
    env = {
        "GENERATOR": "$(rlocationpath :gen_tokens)",
        "KTFMT": "$(rlocationpath //tools/format:ktfmt)",
        "TOKENS": "$(rlocationpath //packages/design-system:src/tokens.json)",
        "HEADER": "$(rlocationpath kt_license_header.txt)",
        "CHECKED_IN": "$(rlocationpath //packages/design-system-android:src/main/kotlin/dev/vitruvian/design/VitruvianTokens.kt)",
    },
    rustc_flags = ["-Copt-level=3"],
    deps = [":gen_tokens_lib"],
)

exports_files([
    "kt_license_header.txt",
    "src/parity_test.rs",
    "src/tokens_are_current.rs",
])
