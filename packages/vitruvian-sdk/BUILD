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

# //packages/vitruvian-sdk: what a tool that runs as its own program is built
# against. The protocol between such a tool and the Vitruvian desktop app, as
# JSON Schema (protocol/) and as Swift (Sources/VitruvianToolProtocol). See
# README.md.
#
# Swift has no Gazelle extension here, so this file is hand-written, and
# Gazelle is kept out of the folders below it: it would write BUILD files for
# the Python it finds there.
# gazelle:ignore
# gazelle:exclude Sources
# gazelle:exclude Tests
# gazelle:exclude conformance
# gazelle:exclude protocol
#
# MUST MIRROR Package.swift target for target (packages/peripherals/BUILD says
# why). The Swift targets are constrained to macOS so a Linux
# `bazel build //...` skips them.

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_test")
load("@build_bazel_rules_swift//swift:swift_library.bzl", "swift_library")
load("@build_bazel_rules_swift//swift:swift_test.bzl", "swift_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# The protocol as it is written down: the schemas, the table of messages, and
# the examples both halves of the drift test read.
PROTOCOL_FILES = glob(["protocol/**/*.json"])

# The smallest tool that speaks the protocol. The conformance script is proven
# against it, and its manifest is read by both halves of the drift test.
REFERENCE_TOOL = glob(["conformance/reference-tool/**"])

REFERENCE_MANIFEST = "conformance/reference-tool/vitruvian-tool.json"

# The one list of the protocol's Swift sources: it is both what the module
# compiles and what the Vitruvian app's pin hashes
# (//apps/desktop/vitruvian:tool_protocol_pin_test), so the two cannot differ.
filegroup(
    name = "protocol_sources",
    srcs = glob(["Sources/VitruvianToolProtocol/**/*.swift"]),
    visibility = ["//apps/desktop/vitruvian:__pkg__"],
)

# The protocol as Swift types. Foundation only. Swift 6 mode because the app's
# Core module, which links it, is. Nothing here may import a Vitruvian module:
# the dependency runs one way, MIT into GPL. Visible to the app and to this
# package, and to nothing else until the package is published.
swift_library(
    name = "VitruvianToolProtocol",
    srcs = [":protocol_sources"],
    features = ["swift.enable_v6"],
    module_name = "VitruvianToolProtocol",
    target_compatible_with = ["@platforms//os:macos"],
    visibility = ["//apps/desktop/vitruvian:__pkg__"],
)

# What a tool is written with, in Swift: declare commands, handle them, call
# the app. It works on one thread and starts none. Foundation and the
# protocol only, and nothing of the app.
swift_library(
    name = "VitruvianToolKit",
    srcs = glob(["Sources/VitruvianToolKit/**/*.swift"]),
    features = ["swift.enable_v6"],
    module_name = "VitruvianToolKit",
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":VitruvianToolProtocol"],
)

# macOS-only and `manual`, like every swift_test in the repository, so the
# Linux lane never names it; the `vitruvian-sdk` pipeline unit below runs it by
# explicit label on xcode-27.
swift_test(
    name = "VitruvianToolProtocolTests",
    size = "small",
    srcs = glob(["Tests/VitruvianToolProtocolTests/**/*.swift"]),
    data = PROTOCOL_FILES + [REFERENCE_MANIFEST],
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":VitruvianToolProtocol"],
)

# The kit against a link made of two files. It starts no process.
swift_test(
    name = "VitruvianToolKitTests",
    size = "small",
    srcs = glob(["Tests/VitruvianToolKitTests/**/*.swift"]),
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":VitruvianToolKit"],
)

# The examples, judged by the schemas. Not `manual` and not tied to macOS: it
# is plain Python, so the Linux lane runs it too.
py_test(
    name = "protocol_examples_test",
    size = "small",
    srcs = ["protocol/protocol_examples_test.py"],
    data = PROTOCOL_FILES + [REFERENCE_MANIFEST],
    main = "protocol/protocol_examples_test.py",
    deps = ["@pip//jsonschema"],
)

# bazel run //packages/vitruvian-sdk:conformance -- <a tool's folder>
#
# Plays the app's side of the protocol to any tool. Plain Python with no
# dependencies, so a tool's author can also run the file itself.
#
# The program is not itself named `conformance`: its launcher would then sit
# in the runfiles where the conformance/ folder must be, and it could not
# find its own script. The alias gives it the name without the file.
py_binary(
    name = "conformance_script",
    srcs = ["conformance/conformance.py"],
    main = "conformance/conformance.py",
)

alias(
    name = "conformance",
    actual = ":conformance_script",
)

# The reference tool passes, and tools that each break the protocol in one way
# are each caught by the check meant for them. It starts real processes:
# Python ones, a few seconds in all. Not `manual` and not tied to macOS, so
# the Linux lane runs it too.
py_test(
    name = "conformance_test",
    size = "small",
    srcs = [
        "conformance/conformance.py",
        "conformance/conformance_test.py",
    ],
    data = REFERENCE_TOOL,
    main = "conformance/conformance_test.py",
)

pipeline_unit(
    name = "vitruvian-sdk",
    persona = "platform",
    runner = "xcode-27",
    test_targets = [
        ":VitruvianToolKitTests",
        ":VitruvianToolProtocolTests",
        ":conformance_test",
        ":protocol_examples_test",
    ],
    tier = "L1",
    timeout_minutes = 30,
)
