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
#   bazel run //tools/sdk-codegen
#
# Hand-written: Gazelle is kept out of emitters/, which holds one module per
# language and is found by looking, not by a list.
# gazelle:ignore
# gazelle:exclude emitters

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_test")

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
    name = "sdk-codegen",
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
