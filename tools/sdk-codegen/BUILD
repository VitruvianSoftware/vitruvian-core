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

# //tools/sdk-codegen: writes each kit's types from the tool protocol's
# schemas (packages/vitruvian-sdk/protocol). See sdk_codegen.py.
#
#   bazel run //tools/sdk-codegen        the Rust port (src/), the default
#   bazel run //tools/sdk-codegen:sdk-codegen-py
#
# Hand-written: Gazelle is kept out of emitters/, which holds one module per
# language and is found by looking, not by a list.
# gazelle:ignore
# gazelle:exclude emitters

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# The emitters are found by looking, so a folder with none is allowed here;
# sdk_codegen_test fails when an emitter it expects is missing.
GENERATOR = [
    "model.py",
    "sdk_codegen.py",
] + glob(
    ["emitters/*.py"],
    allow_empty = True,
)

# What the generator reads, and what it wrote that is committed.
INPUTS = [
    "//packages/vitruvian-sdk:generated_kit_files",
    "//packages/vitruvian-sdk:protocol_files",
]

py_binary(
    name = "sdk-codegen-py",
    srcs = GENERATOR,
    imports = ["."],
    main = "sdk_codegen.py",
    deps = ["@pip//jsonschema"],
)

# Regenerates in memory and compares with the committed files, every one under
# a folder named `generated` in the kits. Not `manual`, so the Linux lane runs it.
py_test(
    name = "in_sync_test",
    size = "small",
    srcs = GENERATOR,
    args = [
        "--check",
        "--package",
        "packages/vitruvian-sdk",
    ],
    data = INPUTS,
    imports = ["."],
    main = "sdk_codegen.py",
    deps = ["@pip//jsonschema"],
)

# The model reads all of the protocol, and a planted change to a schema
# changes what is written and fails the check.
py_test(
    name = "sdk_codegen_test",
    size = "small",
    srcs = GENERATOR + ["sdk_codegen_test.py"],
    data = INPUTS,
    imports = ["."],
    main = "sdk_codegen_test.py",
    deps = ["@pip//jsonschema"],
)

# The same generator in Rust, for speed: the default `:sdk-codegen`. It takes
# no crate, not even serde_json: it must read JSON as Python's json does (key
# order, NaN, its error messages), validate a schema as jsonschema does and
# word the error as it does, and wrap, diff and parse a command line as
# textwrap, difflib and argparse do, so it carries each of those itself.
# src/unicode_tables.rs is written by gen_unicode_tables.py. Optimised in
# every build mode.
rust_library(
    name = "sdk_codegen_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "sdk_codegen",
    crate_root = "src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "sdk-codegen",
    srcs = ["src/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":sdk_codegen_lib"],
)

alias(
    name = "sdk-codegen-rs",
    actual = ":sdk-codegen",
)

alias(
    name = "sdk_codegen_rs",
    actual = ":sdk-codegen",
)

rust_test(
    name = "sdk_codegen_lib_test",
    size = "small",
    crate = ":sdk_codegen_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# Holds the Rust binary to the Python script: every scenario of
# sdk_codegen_test.py, the real protocol, and schemas, files and command
# lines built to break them, run through both, comparing exit codes, stdout,
# stderr and every file written.
py_test(
    name = "sdk_codegen_rs_parity_test",
    size = "medium",
    srcs = GENERATOR + [
        "gen_unicode_tables.py",
        "sdk_codegen_rs_parity_test.py",
        "sdk_codegen_test.py",
    ],
    data = INPUTS + [
        "src/metaschema.rs",
        "src/unicode_tables.rs",
        ":sdk-codegen",
    ],
    env = {"SDK_CODEGEN_RS": "$(rootpath :sdk-codegen)"},
    imports = ["."],
    main = "sdk_codegen_rs_parity_test.py",
    deps = ["@pip//jsonschema"],
)
