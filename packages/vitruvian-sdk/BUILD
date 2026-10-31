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
# gazelle:exclude docs
# gazelle:exclude kits
# gazelle:exclude protocol
# gazelle:exclude samples
# gazelle:exclude verification
#
# The Go kit, go/, is the one folder Gazelle writes: go/BUILD names its
# module. The Rust kit, kits/rust, has a hand-written BUILD of its own.
#
# MUST MIRROR Package.swift target for target (packages/peripherals/BUILD says
# why). The Swift targets are constrained to macOS so a Linux
# `bazel build //...` skips them.

load("@aspect_rules_js//js:defs.bzl", "js_library")
load("@aspect_rules_py//py:defs.bzl", "py_library", "py_test")
load("@bazel_lib//lib:copy_to_directory.bzl", "copy_to_directory")
load("@build_bazel_rules_swift//swift:swift_binary.bzl", "swift_binary")
load("@build_bazel_rules_swift//swift:swift_library.bzl", "swift_library")
load("@build_bazel_rules_swift//swift:swift_test.bzl", "swift_test")
load("@rules_go//go:def.bzl", "go_binary")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")
load("//tools/pytest:defs.bzl", pytest_test = "py_test")

# The protocol as it is written down: the schemas, the table of messages, and
# the examples both halves of the drift test read.
PROTOCOL_FILES = glob(["protocol/**/*.json"])

# The protocol's files, for the TypeScript kit's tests, which read the
# examples as the Swift tests and protocol_examples_test do. A js_library,
# because rules_js copies a test's data into the output tree and will take a
# file from another package only that way.
js_library(
    name = "protocol_files",
    srcs = PROTOCOL_FILES,
    visibility = [
        "//packages/vitruvian-sdk:__subpackages__",
        "//tools/sdk-codegen:__pkg__",
    ],
)

# Every file //tools/sdk-codegen wrote into the kits, for its drift test. A kit
# in a Bazel package of its own lists its generated files there.
filegroup(
    name = "generated_kit_files",
    srcs = glob(["kits/python/vitruvian_tool_kit/generated/**"]) + [
        "//packages/vitruvian-sdk/go/toolkit:protocol_gen.go",
        "//packages/vitruvian-sdk/kits/rust:src/generated/mod.rs",
        "//packages/vitruvian-sdk/kits/typescript:generated",
    ],
    visibility = ["//tools/sdk-codegen:__pkg__"],
)

# The smallest tools that speak the protocol, one for version 1 and one for
# version 2. The conformance script is proven against both, and their
# manifests are read by both halves of the drift test.
REFERENCE_TOOL = glob(["conformance/reference-tool/**"])

REFERENCE_TOOL_2 = glob(["conformance/reference-tool-2/**"])

REFERENCE_MANIFESTS = [
    "conformance/reference-tool/vitruvian-tool.json",
    "conformance/reference-tool-2/vitruvian-tool.json",
]

# The one list of the protocol's Swift sources: it is both what the module
# compiles and what the Vitruvian app's pin hashes
# (//apps/desktop/vitruvian:tool_protocol_pin_test), so the two cannot differ.
filegroup(
    name = "protocol_sources",
    srcs = glob(["Sources/VitruvianToolProtocol/**/*.swift"]),
    visibility = ["//packages/vitruvian-sdk/consumers:app"],
)

# The protocol as Swift types. Foundation only. Swift 6 mode because the app's
# Core module, which links it, is. Nothing here may import a Vitruvian module:
# the dependency runs one way, MIT into GPL. Visible to the app, to the tools
# built here and to this package. Who that is, is listed in consumers/BUILD:
# add a new tool there, not here, or its pull request cuts an SDK release.
swift_library(
    name = "VitruvianToolProtocol",
    srcs = [":protocol_sources"],
    features = ["swift.enable_v6"],
    module_name = "VitruvianToolProtocol",
    target_compatible_with = ["@platforms//os:macos"],
    visibility = [
        "//packages/vitruvian-sdk/consumers:app",
        "//packages/vitruvian-sdk/consumers:tools",
    ],
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
    visibility = ["//packages/vitruvian-sdk/consumers:tools"],
    deps = [":VitruvianToolProtocol"],
)

# Folders the command-line tool and the app must judge alike. The app's own
# tests read the same file, which is why it can see it.
filegroup(
    name = "folder_examples",
    srcs = ["protocol/examples/folders.json"],
    visibility = ["//packages/vitruvian-sdk/consumers:app"],
)

# What the Tools section of vitruviansoftware.dev is copied from
# (//tools/sync-site-tools), so its test sees the same files.
filegroup(
    name = "site_sources",
    srcs = [
        "docs/writing-a-tool.md",
        "protocol/README.md",
        "protocol/methods.json",
        "samples/hello-go/README.md",
        "samples/hello-python-kit/README.md",
        "samples/hello-python/bin/tool.py",
        "samples/hello-python/vitruvian-tool.json",
        "samples/hello-rust/README.md",
        "samples/hello-swift/main.swift",
        "samples/hello-swift/vitruvian-tool.json",
        "samples/hello-typescript/README.md",
    ],
    visibility = ["//tools/sync-site-tools:__pkg__"],
)

# The protocol's example messages. The app's tests hold what the app sends a
# tool to the example of it here.
filegroup(
    name = "message_examples",
    srcs = ["protocol/examples/messages.json"],
    visibility = ["//packages/vitruvian-sdk/consumers:app"],
)

# Everything the `vitruvian-tool` command does, as a library so the tests can
# link it without the executable's top-level code, which would collide with
# XCTest's `main`.
swift_library(
    name = "VitruvianToolCLI",
    srcs = glob(["Sources/VitruvianToolCLI/**/*.swift"]),
    features = ["swift.enable_v6"],
    module_name = "VitruvianToolCLI",
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":VitruvianToolProtocol"],
)

# bazel run --config=macos-app //packages/vitruvian-sdk:vitruvian-tool -- validate <a tool's folder>
#
# `manual` and macOS-only, like the app's own swift_binary targets.
swift_binary(
    name = "vitruvian-tool",
    srcs = glob(["Sources/vitruvian-tool/**/*.swift"]),
    features = ["swift.enable_v6"],
    module_name = "VitruvianToolCommandLine",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    # The GitHub, Nexus Agent and HomeSpeaker tools' folder tests run `validate` on what
    # they built.
    visibility = ["//packages/vitruvian-sdk/consumers:tools"],
    deps = [":VitruvianToolCLI"],
)

# macOS-only and `manual`, like every swift_test in the repository, so the
# Linux lane never names it; the `vitruvian-sdk` pipeline unit below runs it by
# explicit label on xcode-27.
swift_test(
    name = "VitruvianToolProtocolTests",
    size = "small",
    srcs = glob(["Tests/VitruvianToolProtocolTests/**/*.swift"]),
    data = PROTOCOL_FILES + REFERENCE_MANIFESTS,
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

# The command against folders it makes in the temporary folder, and against
# real processes: shell scripts it writes there, and the built Swift sample.
# The built command is there to be started and interrupted.
swift_test(
    name = "VitruvianToolCLITests",
    size = "small",
    srcs = glob(["Tests/VitruvianToolCLITests/**/*.swift"]),
    data = PROTOCOL_FILES + glob([
        "Sources/VitruvianToolCLI/**/*.swift",
        "samples/**",
    ]) + [
        "built/hello-swift/vitruvian-tool.json",
        ":hello-swift-folder",
        ":vitruvian-tool",
    ],
    env = {
        "VITRUVIAN_HELLO_SWIFT": "$(rootpath built/hello-swift/vitruvian-tool.json)",
        "VITRUVIAN_TOOL_BINARY": "$(rootpath :vitruvian-tool)",
    },
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        ":VitruvianToolCLI",
        ":VitruvianToolProtocol",
    ],
)

# The examples, judged by the schemas, and every line the reference tool of
# protocol 2 writes in a short session. Not `manual` and not tied to macOS:
# plain Rust, so the Linux lane runs it too. verification/Cargo.toml runs the
# same program in the mirror.
rust_test(
    name = "protocol_examples_test",
    size = "small",
    srcs = ["verification/src/bin/protocol_examples_test.rs"],
    crate_root = "verification/src/bin/protocol_examples_test.rs",
    data = PROTOCOL_FILES + REFERENCE_MANIFESTS + [
        "conformance/reference-tool-2/bin/reference_tool_2.py",
        ":reference-tool-2-rs",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    use_libtest_harness = False,
    deps = [":verification_rs_lib"],
)

test_suite(
    name = "protocol_examples_rs_test",
    tests = [":protocol_examples_test"],
)

# bazel run //packages/vitruvian-sdk:conformance -- <a tool's folder>
#
# Plays the app's side of the protocol to any tool (std only, zero external
# crates).
rust_library(
    name = "conformance_rs_lib",
    srcs = glob(
        ["conformance/src/**/*.rs"],
        exclude = ["conformance/src/main.rs"],
    ),
    crate_name = "conformance_rs_lib",
    crate_root = "conformance/src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//packages/vitruvian-sdk/consumers:tools"],
)

rust_binary(
    name = "conformance",
    srcs = ["conformance/src/main.rs"],
    crate_root = "conformance/src/main.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//packages/vitruvian-sdk/consumers:tools"],
    deps = [":conformance_rs_lib"],
)

alias(
    name = "conformance-rs",
    actual = ":conformance",
    visibility = ["//packages/vitruvian-sdk/consumers:tools"],
)

alias(
    name = "conformance_rs",
    actual = ":conformance",
    visibility = ["//packages/vitruvian-sdk/consumers:tools"],
)

rust_test(
    name = "conformance_rs_lib_test",
    size = "small",
    crate = ":conformance_rs_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

# The reference tools pass, one for each protocol version, and tools that
# each break the protocol in one way are each caught by the check meant for
# them. Not `manual` and not tied to macOS, so the Linux lane runs it too.
rust_test(
    name = "conformance_test",
    size = "small",
    srcs = ["verification/src/bin/conformance_test.rs"],
    crate_root = "verification/src/bin/conformance_test.rs",
    data = REFERENCE_TOOL + REFERENCE_TOOL_2,
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    use_libtest_harness = False,
    deps = [":verification_rs_lib"],
)

test_suite(
    name = "conformance_rs_test",
    tests = [":conformance_test"],
)

# Native Rust verification suites and reference tools (std + conformance_rs_lib only,
# zero external crates).
rust_library(
    name = "verification_rs_lib",
    srcs = glob(
        ["verification/src/*.rs"],
    ),
    crate_name = "verification_rs_lib",
    crate_root = "verification/src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":conformance_rs_lib"],
)

rust_test(
    name = "verification_rs_lib_test",
    size = "small",
    crate = ":verification_rs_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "reference-tool-rs",
    srcs = ["verification/src/bin/reference_tool.rs"],
    crate_root = "verification/src/bin/reference_tool.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":verification_rs_lib"],
)

alias(
    name = "reference_tool_rs",
    actual = ":reference-tool-rs",
)

rust_binary(
    name = "reference-tool-2-rs",
    srcs = ["verification/src/bin/reference_tool_2.rs"],
    crate_root = "verification/src/bin/reference_tool_2.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":verification_rs_lib"],
)

alias(
    name = "reference_tool_2_rs",
    actual = ":reference-tool-2-rs",
)

# --- The samples ---------------------------------------------------------------
# Four tools a person can add to the app. Each is a folder with a manifest
# and a program. The Python one is that folder as it stands in samples/. A
# Swift one is put together by Bazel, because its program has to be built:
#
#   bazel build --config=macos-app //packages/vitruvian-sdk:sample-folders
#
# leaves bazel-bin/packages/vitruvian-sdk/built/<sample>/, with the manifest
# and bin/tool, and that folder is what the app is pointed at.

# The samples written in Swift: the folder under samples/, and the module its
# program is compiled as.
SWIFT_SAMPLES = {
    "front-window": "FrontWindowSample",
    "hello-panel-swift": "HelloPanelSwiftSample",
    "hello-swift": "HelloSwiftSample",
}

# `manual` and macOS-only, like the app's own swift_binary targets: a Linux
# `bazel build //...` never names them.
[
    swift_binary(
        name = sample,
        srcs = ["samples/%s/main.swift" % sample],
        features = ["swift.enable_v6"],
        module_name = module,
        tags = ["manual"],
        target_compatible_with = ["@platforms//os:macos"],
        deps = [":VitruvianToolKit"],
    )
    for sample, module in SWIFT_SAMPLES.items()
]

[
    genrule(
        name = sample + "-folder",
        srcs = [
            "samples/%s/vitruvian-tool.json" % sample,
            ":" + sample,
        ],
        outs = [
            "built/%s/vitruvian-tool.json" % sample,
            "built/%s/bin/tool" % sample,
        ],
        cmd = "cp $(location samples/%s/vitruvian-tool.json) $(RULEDIR)/built/%s/vitruvian-tool.json && cp $(location :%s) $(RULEDIR)/built/%s/bin/tool" % (sample, sample, sample, sample),
        tags = ["manual"],
        target_compatible_with = ["@platforms//os:macos"],
    )
    for sample in SWIFT_SAMPLES
]

filegroup(
    name = "sample-folders",
    srcs = [":%s-folder" % sample for sample in SWIFT_SAMPLES],
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
)

# The samples written in Go and in Rust, built with the hermetic toolchains,
# so not tied to macOS: the Linux lane builds them and puts them through
# the conformance script too.
go_binary(
    name = "hello-go",
    srcs = ["samples/hello-go/main.go"],
    deps = ["//packages/vitruvian-sdk/go/toolkit"],
)

go_binary(
    name = "hello-panel-go",
    srcs = ["samples/hello-panel-go/main.go"],
    deps = [
        "//packages/vitruvian-sdk/go/toolkit",
        "//packages/vitruvian-sdk/go/toolkit/ui",
    ],
)

rust_binary(
    name = "hello-rust",
    srcs = ["samples/hello-rust/src/main.rs"],
    edition = "2021",
    deps = ["//packages/vitruvian-sdk/kits/rust:vitruvian_tool_kit"],
)

rust_binary(
    name = "hello-panel-rust",
    srcs = ["samples/hello-panel-rust/src/main.rs"],
    edition = "2021",
    deps = ["//packages/vitruvian-sdk/kits/rust:vitruvian_tool_kit"],
)

# By language: the samples the language's own `<language>_sample_test`
# puts through the conformance script, one after the other.
NATIVE_SAMPLES = {
    "go": [
        "hello-go",
        "hello-panel-go",
    ],
    "rust": [
        "hello-rust",
        "hello-panel-rust",
    ],
}

NATIVE_SAMPLE_FOLDERS = [sample for samples in NATIVE_SAMPLES.values() for sample in samples]

[
    genrule(
        name = sample + "-folder",
        srcs = [
            "samples/%s/vitruvian-tool.json" % sample,
            ":" + sample,
        ],
        outs = [
            "built/%s/vitruvian-tool.json" % sample,
            "built/%s/bin/tool" % sample,
        ],
        cmd = "cp $(location samples/%s/vitruvian-tool.json) $(RULEDIR)/built/%s/vitruvian-tool.json && cp $(location :%s) $(RULEDIR)/built/%s/bin/tool" % (sample, sample, sample, sample),
    )
    for sample in NATIVE_SAMPLE_FOLDERS
]

#   bazel build //packages/vitruvian-sdk:native-sample-folders
#
# leaves bazel-bin/packages/vitruvian-sdk/built/hello-go and hello-rust, each
# with its manifest and bin/tool, on any Mac or Linux machine.
filegroup(
    name = "native-sample-folders",
    srcs = [":%s-folder" % sample for sample in NATIVE_SAMPLE_FOLDERS],
)

# Each built sample against the conformance validator. They start real
# processes, a second or two each. Not `manual` and not tied to macOS, so the
# Linux lane runs them too.
[
    rust_test(
        name = language + "_sample_test",
        size = "small",
        srcs = ["verification/src/bin/samples_test.rs"],
        args = ["$(rootpath built/%s/vitruvian-tool.json)" % sample for sample in samples],
        crate_root = "verification/src/bin/samples_test.rs",
        data = [":%s-folder" % sample for sample in samples] + ["built/%s/vitruvian-tool.json" % sample for sample in samples],
        edition = "2021",
        rustc_flags = ["-Copt-level=3"],
        use_libtest_harness = False,
        deps = [":verification_rs_lib"],
    )
    for language, samples in NATIVE_SAMPLES.items()
]

[
    test_suite(
        name = language + "_sample_rs_test",
        tests = [":" + language + "_sample_test"],
    )
    for language in NATIVE_SAMPLES
]

# What needs no build: every sample's manifest against the schema, one SDK
# version across the kits, the kit samples and the command, and the plain
# Python sample against the conformance validator. Not `manual` and not tied to
# macOS, so the Linux lane runs it too.
rust_test(
    name = "samples_test",
    size = "small",
    srcs = ["verification/src/bin/samples_test.rs"],
    crate_root = "verification/src/bin/samples_test.rs",
    data = glob([
        "samples/**",
        "Sources/VitruvianToolCLI/*.swift",
    ]) + [
        "kits/python/pyproject.toml",
        "protocol/manifest.schema.json",
        "//packages/vitruvian-sdk/go/toolkit:version.go",
        "//packages/vitruvian-sdk/kits/rust:Cargo.toml",
        "//packages/vitruvian-sdk/kits/typescript:package.json",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    use_libtest_harness = False,
    deps = [":verification_rs_lib"],
)

test_suite(
    name = "samples_rs_test",
    tests = [":samples_test"],
)

# The Swift samples, built, against the conformance validator. It starts
# real processes. `manual` and macOS-only: the pipeline unit names it.
rust_test(
    name = "swift_samples_test",
    size = "small",
    srcs = ["verification/src/bin/samples_test.rs"],
    args = ["$(rootpath built/%s/vitruvian-tool.json)" % sample for sample in SWIFT_SAMPLES],
    crate_root = "verification/src/bin/samples_test.rs",
    data = [":sample-folders"] + ["built/%s/vitruvian-tool.json" % sample for sample in SWIFT_SAMPLES] + glob(["samples/**"]),
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    use_libtest_harness = False,
    deps = [":verification_rs_lib"],
)

test_suite(
    name = "swift_samples_rs_test",
    tags = ["manual"],
    tests = [":swift_samples_test"],
)

# The mirror's own workflows (.github/workflows/, which run only in
# VitruvianSoftware/vitruvian-sdk): release.yml's `detect` step, run as written
# with bash, git and jq, releases a version once and never 0.0.0; and no job
# may write more than it must. `no-remote-exec`: the step needs jq and git on
# the machine, and the remote execution image has no jq.
rust_test(
    name = "mirror_workflows_test",
    size = "small",
    srcs = ["verification/src/bin/mirror_workflows_test.rs"],
    crate_root = "verification/src/bin/mirror_workflows_test.rs",
    data = [
        ".github/workflows/ci.yml",
        ".github/workflows/kits.yml",
        ".github/workflows/release.yml",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    tags = ["no-remote-exec"],
    use_libtest_harness = False,
    deps = [":verification_rs_lib"],
)

# --- The kits ------------------------------------------------------------------
# The TypeScript kit has a BUILD of its own (kits/typescript/BUILD): rules_js
# links a package's node_modules in that package's folder. The Python kit is
# here. Part of each is generated by //tools/sdk-codegen.

# The Python kit: standard library only, Python 3.9 and later.
py_library(
    name = "vitruvian_tool_kit",
    srcs = glob(["kits/python/vitruvian_tool_kit/**/*.py"]),
    imports = ["kits/python"],
    visibility = ["//visibility:public"],
)

# The thirteen tests of the Swift kit's ToolTests, the kit's own, and the
# generated types against the protocol's examples. pytest runs them here, as
# the repository runs Python tests; they are written with unittest, so an
# author or the mirror runs them with nothing installed. Not `manual` and not
# tied to macOS, so the Linux lane runs it too.
pytest_test(
    name = "python_kit_test",
    size = "small",
    srcs = glob(["kits/python/tests/test_*.py"]),
    data = PROTOCOL_FILES,
    deps = [":vitruvian_tool_kit"],
)

# The same tests with the python3 macOS ships, /usr/bin/python3: the one the
# app finds when it starts a tool, Python 3.9 today, so the kit must run on
# it. Not hermetic, so `manual` and macOS-only: the pipeline unit names it.
py_test(
    name = "python_kit_apple_python_test",
    size = "small",
    srcs = ["kits/apple_python_test.py"],
    data = glob(["kits/python/**/*.py"]) + PROTOCOL_FILES,
    main = "kits/apple_python_test.py",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
)

# The kit samples' folders as an author ships them: the TypeScript one with
# the built kit in node_modules/, as `npm install` leaves it; the Python one
# with the kit in lib/, as `pip install --target lib` leaves it.
copy_to_directory(
    name = "hello-typescript-folder",
    srcs = glob(["samples/hello-typescript/**"]) + ["//packages/vitruvian-sdk/kits/typescript:tool-kit-typescript"],
    out = "built/hello-typescript",
    replace_prefixes = {
        "samples/hello-typescript/": "",
        "kits/typescript/tool-kit-typescript": "node_modules/@vitruviansoftware/tool-kit",
    },
)

copy_to_directory(
    name = "hello-panel-typescript-folder",
    srcs = glob(["samples/hello-panel-typescript/**"]) + ["//packages/vitruvian-sdk/kits/typescript:tool-kit-typescript"],
    out = "built/hello-panel-typescript",
    replace_prefixes = {
        "samples/hello-panel-typescript/": "",
        "kits/typescript/tool-kit-typescript": "node_modules/@vitruviansoftware/tool-kit",
    },
)

copy_to_directory(
    name = "hello-panel-python-folder",
    srcs = glob(["samples/hello-panel-python/**"]) + glob(["kits/python/vitruvian_tool_kit/**/*.py"]),
    out = "built/hello-panel-python",
    replace_prefixes = {
        "samples/hello-panel-python/": "",
        "kits/python/vitruvian_tool_kit/": "lib/vitruvian_tool_kit/",
    },
)

copy_to_directory(
    name = "hello-python-kit-folder",
    srcs = glob(["samples/hello-python-kit/**"]) + glob(["kits/python/vitruvian_tool_kit/**/*.py"]),
    out = "built/hello-python-kit",
    replace_prefixes = {
        "samples/hello-python-kit/": "",
        "kits/python/vitruvian_tool_kit/": "lib/vitruvian_tool_kit/",
    },
)

# The kit samples, as shipped, against the conformance validator. It starts
# real processes: Node through the sample's own bin/tool, which finds `node`
# on the PATH the test gives it, and the Python sample through Python. Not
# `manual` and not tied to macOS, so the Linux lane runs it.
rust_test(
    name = "kit_samples_test",
    size = "small",
    srcs = ["verification/src/bin/samples_test.rs"],
    args = [
        "$(rootpath :hello-typescript-folder)/vitruvian-tool.json",
        "$(rootpath :hello-python-kit-folder)/vitruvian-tool.json",
        "$(rootpath :hello-panel-typescript-folder)/vitruvian-tool.json",
        "$(rootpath :hello-panel-python-folder)/vitruvian-tool.json",
    ],
    crate_root = "verification/src/bin/samples_test.rs",
    data = [
        ":hello-panel-python-folder",
        ":hello-panel-typescript-folder",
        ":hello-python-kit-folder",
        ":hello-typescript-folder",
        "@nodejs_toolchains//:resolved_toolchain",
    ],
    edition = "2021",
    env = {"VITRUVIAN_NODE": "$(NODE_PATH)"},
    rustc_flags = ["-Copt-level=3"],
    toolchains = ["@nodejs_toolchains//:resolved_toolchain"],
    use_libtest_harness = False,
    deps = [":verification_rs_lib"],
)

test_suite(
    name = "kit_samples_rs_test",
    tests = [":kit_samples_test"],
)

# `vitruvian-tool init` starts a new tool from a copy of a hello sample, and
# the copies are compiled into the command as text. This writes that text:
#
#   bazel run //packages/vitruvian-sdk:sync-templates
rust_library(
    name = "sync_templates_rs_lib",
    srcs = ["samples/src/lib.rs"],
    crate_name = "sync_templates_rs_lib",
    crate_root = "samples/src/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_binary(
    name = "sync-templates",
    srcs = ["samples/src/main.rs"],
    crate_root = "samples/src/main.rs",
    data = glob(["samples/hello-*/**"]),
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":sync_templates_rs_lib"],
)

alias(
    name = "sync-templates-rs",
    actual = ":sync-templates",
)

alias(
    name = "sync_templates_rs",
    actual = ":sync-templates",
)

# The committed text is what the samples are now. Not `manual` and not tied
# to macOS, so the Linux lane runs it too.
rust_test(
    name = "templates_in_sync_test",
    size = "small",
    crate = ":sync_templates_rs_lib",
    data = glob(["samples/hello-*/**"]) + [
        "Sources/VitruvianToolCLI/Templates.swift",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

test_suite(
    name = "sync_templates_rs_lib_test",
    tests = [":templates_in_sync_test"],
)

# What `init` writes passes `validate`, the conformance validator and `run`. It
# starts the built command and real processes. `manual` and macOS-only.
rust_test(
    name = "init_test",
    size = "small",
    srcs = ["verification/src/bin/init_test.rs"],
    args = ["$(rootpath :vitruvian-tool)"],
    crate_root = "verification/src/bin/init_test.rs",
    data = [
        "Package.swift",
        ":vitruvian-tool",
        "//packages/vitruvian-sdk/kits/typescript:tool-kit-typescript",
        "@nodejs_toolchains//:resolved_toolchain",
    ] + glob(["kits/python/vitruvian_tool_kit/**/*.py"]),
    edition = "2021",
    env = {
        "VITRUVIAN_NODE": "$(NODE_PATH)",
        "VITRUVIAN_TOOL_KIT_TYPESCRIPT": "$(rootpath //packages/vitruvian-sdk/kits/typescript:tool-kit-typescript)",
    },
    rustc_flags = ["-Copt-level=3"],
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    toolchains = ["@nodejs_toolchains//:resolved_toolchain"],
    use_libtest_harness = False,
    deps = [":verification_rs_lib"],
)

test_suite(
    name = "init_rs_test",
    tags = ["manual"],
    tests = [":init_test"],
)

# The Swift tool `init --template swift` writes, built the way its author
# builds it: the test runs the `build.sh` it wrote, which is `swift build`
# with the Mac's own Swift toolchain, not Bazel's. It builds against a copy of
# this package, so the package's `Package.swift` is built here too. Then
# `validate` and `run` are held to pass on what was built.
#
# Not hermetic, so `no-sandbox` and `no-remote`, as the app's unit tests are,
# and `manual` and macOS-only: the pipeline unit names it. It needs no
# network: the tool's one dependency is the copy of this package beside it.
# What it gives `swift build`, and why, all of it inside the test's own
# temporary folder, which it deletes:
#   HOME, CFFIXED_USER_HOME  SwiftPM's caches and configuration go under the
#                            home folder, and Foundation asks the second.
#   TMPDIR                   SwiftPM's own temporary folders and lock files.
#   CLANG_MODULE_CACHE_PATH  the compiler's module cache.
# PATH, and DEVELOPER_DIR when set, are passed on. Nothing else is.
# On Swift 6.4 a clean `swift build` leaves one empty folder,
# `TemporaryDirectory.XXXXXX` holding an empty `.keep-directory`, in the
# Mac's real per-user temporary folder, whatever the environment says. The
# test takes away the ones its own build made, and no others: see `sweep`.
rust_test(
    name = "swift_template_test",
    size = "large",
    timeout = "long",
    srcs = ["verification/src/bin/swift_template_test.rs"],
    args = ["$(rootpath :vitruvian-tool)"],
    crate_root = "verification/src/bin/swift_template_test.rs",
    data = [
        "Package.swift",
        ":vitruvian-tool",
    ] + glob([
        "Sources/**",
        "Tests/**",
        "samples/**",
    ]),
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    tags = [
        "manual",
        "no-remote",
        "no-sandbox",
    ],
    target_compatible_with = ["@platforms//os:macos"],
    use_libtest_harness = False,
    deps = [":verification_rs_lib"],
)

test_suite(
    name = "swift_template_rs_test",
    tags = ["manual"],
    tests = [":swift_template_test"],
)

# The end of the test above: its folder goes even while something is still
# writing into it, and what cannot go is named. Needs no Swift and no Mac.
rust_test(
    name = "swift_template_cleanup_test",
    srcs = ["verification/src/bin/swift_template_cleanup_test.rs"],
    crate_root = "verification/src/bin/swift_template_cleanup_test.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    use_libtest_harness = False,
    deps = [":verification_rs_lib"],
)

test_suite(
    name = "swift_template_cleanup_rs_test",
    tests = [":swift_template_cleanup_test"],
)

# The Go kit as its own module, outside the workspace, through `go vet` with
# Bazel's Go: vet holds it to the Go its go.mod names, 1.22, which the
# build above does not. No network. Not `manual` and not tied to macOS.
GO_KIT = [
    "//packages/vitruvian-sdk/go:go.mod",
    "//packages/vitruvian-sdk/go/toolkit:sources",
    "//packages/vitruvian-sdk/go/toolkit/ui:sources",
]

rust_test(
    name = "go_kit_vet_test",
    size = "small",
    srcs = ["verification/src/bin/go_template_test.rs"],
    args = [
        "$(rootpath //tools/go-sdk:go)",
        "$(rootpaths %s)" % GO_KIT[0],
        "$(rootpaths %s)" % GO_KIT[1],
        "$(rootpaths %s)" % GO_KIT[2],
    ],
    crate_root = "verification/src/bin/go_template_test.rs",
    data = GO_KIT + ["//tools/go-sdk:go"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    use_libtest_harness = False,
    deps = [":verification_rs_lib"],
)

test_suite(
    name = "go_kit_vet_rs_test",
    tests = [":go_kit_vet_test"],
)

# The same, then the tool `init --template go --sdk` writes, built by its
# own build.sh with Bazel's Go first on the PATH, through `validate`, the
# conformance validator and `run`. It starts the built command, so `manual`
# and macOS-only, like init_test.
rust_test(
    name = "go_template_test",
    size = "medium",
    srcs = ["verification/src/bin/go_template_test.rs"],
    args = [
        "$(rootpath //tools/go-sdk:go)",
        "$(rootpaths %s)" % GO_KIT[0],
        "$(rootpaths %s)" % GO_KIT[1],
        "$(rootpaths %s)" % GO_KIT[2],
        "--tool",
        "$(rootpath :vitruvian-tool)",
    ],
    crate_root = "verification/src/bin/go_template_test.rs",
    data = GO_KIT + [
        ":vitruvian-tool",
        "//tools/go-sdk:go",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    use_libtest_harness = False,
    deps = [":verification_rs_lib"],
)

test_suite(
    name = "go_template_rs_test",
    tags = ["manual"],
    tests = [":go_template_test"],
)

# The guide's examples: every message and manifest in it against the schemas,
# every piece of code in it against the sample it is taken from, every
# command in it against what exists, and what it quotes the command as saying
# against the command's own words. Not `manual` and not tied to macOS.
rust_test(
    name = "guide_test",
    size = "small",
    srcs = ["verification/src/bin/guide_test.rs"],
    crate_root = "verification/src/bin/guide_test.rs",
    data = PROTOCOL_FILES + glob(["samples/**"]) + [
        "BUILD",
        "Sources/VitruvianToolCLI/NewTool.swift",
        "Sources/VitruvianToolCLI/Words.swift",
        "docs/writing-a-tool.md",
        "//packages/vitruvian-sdk/go/toolkit:app.go",
        "//packages/vitruvian-sdk/kits/rust:src/app.rs",
    ] + glob(["Sources/VitruvianToolKit/**/*.swift"]),
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    use_libtest_harness = False,
    deps = [":verification_rs_lib"],
)

# The version in release-please's two files and the one `--version` prints
# agree. Plain Rust, so the Linux lane runs it too.
rust_test(
    name = "release_version_test",
    size = "small",
    srcs = ["verification/src/bin/release_version_test.rs"],
    crate_root = "verification/src/bin/release_version_test.rs",
    data = [
        ".release-please-manifest.json",
        "BUILD",
        "Sources/VitruvianToolCLI/Words.swift",
        "kits/python/pyproject.toml",
        "release-please-config.json",
        "samples/hello-go/go.mod",
        "samples/hello-panel-go/go.mod",
        "samples/hello-panel-python/requirements.txt",
        "samples/hello-panel-rust/Cargo.toml",
        "samples/hello-panel-typescript/package.json",
        "samples/hello-python-kit/requirements.txt",
        "samples/hello-rust/Cargo.toml",
        "samples/hello-typescript/package.json",
        "//packages/vitruvian-sdk/go/toolkit:version.go",
        "//packages/vitruvian-sdk/kits/rust:Cargo.toml",
        "//packages/vitruvian-sdk/kits/typescript:package.json",
    ],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    use_libtest_harness = False,
    deps = [":verification_rs_lib"],
)

pipeline_unit(
    name = "vitruvian-sdk",
    persona = "platform",
    runner = "xcode-27",
    test_targets = [
        "//packages/vitruvian-sdk/go/toolkit:toolkit_test",
        "//packages/vitruvian-sdk/kits/rust:protocol_test",
        "//packages/vitruvian-sdk/kits/rust:tool_test",
        "//packages/vitruvian-sdk/kits/typescript:kit_test",
        "//tools/sdk-codegen:in_sync_test",
        "//tools/sdk-codegen:sdk_codegen_test",
        ":VitruvianToolCLITests",
        ":VitruvianToolKitTests",
        ":VitruvianToolProtocolTests",
        ":conformance_test",
        ":go_kit_vet_test",
        ":go_sample_test",
        ":go_template_test",
        ":guide_test",
        ":init_test",
        ":kit_samples_test",
        ":mirror_workflows_test",
        ":protocol_examples_test",
        ":python_kit_apple_python_test",
        ":python_kit_test",
        ":release_version_test",
        ":rust_sample_test",
        ":samples_test",
        ":swift_samples_test",
        ":swift_template_cleanup_test",
        ":swift_template_test",
        ":templates_in_sync_test",
    ],
    tier = "L1",
    timeout_minutes = 30,
)  # What a release bumps. The site's sync test holds that it copies none of it.

# //tools/release-scope's test reads it too: it replays the pull requests that
# let a tool in against this config as it is, to show that doing so releases
# nothing now.
exports_files(
    ["release-please-config.json"],
    visibility = [
        "//tools/release-scope:__pkg__",
        "//tools/sync-site-tools:__pkg__",
    ],
)
