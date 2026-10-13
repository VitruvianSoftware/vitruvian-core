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
# gazelle:exclude protocol
# gazelle:exclude samples
#
# MUST MIRROR Package.swift target for target (packages/peripherals/BUILD says
# why). The Swift targets are constrained to macOS so a Linux
# `bazel build //...` skips them.

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_test")
load("@build_bazel_rules_swift//swift:swift_binary.bzl", "swift_binary")
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

# Folders the command-line tool and the app must judge alike. The app's own
# tests read the same file, which is why it can see it.
filegroup(
    name = "folder_examples",
    srcs = ["protocol/examples/folders.json"],
    visibility = ["//apps/desktop/vitruvian:__pkg__"],
)

# What the Tools section of vitruviansoftware.dev is copied from
# (//tools/sync-site-tools), so its test sees the same files.
filegroup(
    name = "site_sources",
    srcs = [
        "docs/writing-a-tool.md",
        "protocol/README.md",
        "protocol/methods.json",
        "samples/hello-python/bin/tool.py",
        "samples/hello-python/vitruvian-tool.json",
        "samples/hello-swift/main.swift",
        "samples/hello-swift/vitruvian-tool.json",
    ],
    visibility = ["//tools/sync-site-tools:__pkg__"],
)

# The protocol's example messages. The app's tests hold what the app sends a
# tool to the example of it here.
filegroup(
    name = "message_examples",
    srcs = ["protocol/examples/messages.json"],
    visibility = ["//apps/desktop/vitruvian:__pkg__"],
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
    deps = [":VitruvianToolCLI"],
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

# What needs no build: every sample's manifest against the schema, and the
# Python sample against the conformance script. Not `manual` and not tied to
# macOS, so the Linux lane runs it too.
py_test(
    name = "samples_test",
    size = "small",
    srcs = [
        "conformance/conformance.py",
        "samples/samples_test.py",
    ],
    data = glob(["samples/**"]) + ["protocol/manifest.schema.json"],
    main = "samples/samples_test.py",
    deps = ["@pip//jsonschema"],
)

# The Swift samples, built, against the conformance script. It starts
# real processes. `manual` and macOS-only: the pipeline unit names it.
py_test(
    name = "swift_samples_test",
    size = "small",
    srcs = [
        "conformance/conformance.py",
        "samples/samples_test.py",
    ],
    args = ["$(rootpath built/%s/vitruvian-tool.json)" % sample for sample in SWIFT_SAMPLES],
    data = [":sample-folders"] + ["built/%s/vitruvian-tool.json" % sample for sample in SWIFT_SAMPLES] + glob(["samples/**"]),
    main = "samples/samples_test.py",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = ["@pip//jsonschema"],
)

# The mirror's own workflows (.github/workflows/, which run only in
# VitruvianSoftware/vitruvian-sdk): release.yml's `detect` step, run as written
# with bash, git and jq, releases a version once and never 0.0.0; and no job
# may write more than it must. `no-remote-exec`: the step needs jq and git on
# the machine, and the remote execution image has no jq.
py_test(
    name = "mirror_workflows_test",
    size = "small",
    srcs = ["mirror_workflows_test.py"],
    data = [
        ".github/workflows/ci.yml",
        ".github/workflows/release.yml",
    ],
    main = "mirror_workflows_test.py",
    tags = ["no-remote-exec"],
    deps = ["@pip//pyyaml"],
)

# `vitruvian-tool init` starts a new tool from a copy of a hello sample, and
# the copies are compiled into the command as text. This writes that text:
#
#   bazel run //packages/vitruvian-sdk:sync-templates
py_binary(
    name = "sync-templates",
    srcs = ["samples/sync_templates.py"],
    data = glob(["samples/hello-*/**"]),
    main = "samples/sync_templates.py",
)

# The committed text is what the samples are now. Not `manual` and not tied
# to macOS, so the Linux lane runs it too.
py_test(
    name = "templates_in_sync_test",
    size = "small",
    srcs = ["samples/sync_templates.py"],
    args = ["--check"],
    data = glob(["samples/hello-*/**"]) + ["Sources/VitruvianToolCLI/Templates.swift"],
    main = "samples/sync_templates.py",
)

# What `init` writes passes `validate`, the conformance script and `run`. It
# starts the built command and real processes. `manual` and macOS-only.
py_test(
    name = "init_test",
    size = "small",
    srcs = [
        "conformance/conformance.py",
        "samples/init_test.py",
    ],
    args = ["$(rootpath :vitruvian-tool)"],
    data = [
        "Package.swift",
        ":vitruvian-tool",
    ],
    main = "samples/init_test.py",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
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
py_test(
    name = "swift_template_test",
    size = "large",
    timeout = "long",
    srcs = ["samples/swift_template_test.py"],
    args = ["$(rootpath :vitruvian-tool)"],
    data = [
        "Package.swift",
        ":vitruvian-tool",
    ] + glob([
        "Sources/**",
        "Tests/**",
        "samples/**",
    ]),
    main = "samples/swift_template_test.py",
    tags = [
        "manual",
        "no-remote",
        "no-sandbox",
    ],
    target_compatible_with = ["@platforms//os:macos"],
)

# The guide's examples: every message and manifest in it against the schemas,
# every piece of code in it against the sample it is taken from, every
# command in it against what exists, and what it quotes the command as saying
# against the command's own words. Not `manual` and not tied to macOS.
py_test(
    name = "guide_test",
    size = "small",
    srcs = ["docs/guide_test.py"],
    data = PROTOCOL_FILES + glob(["samples/**"]) + [
        "BUILD",
        "Sources/VitruvianToolCLI/Words.swift",
        "Sources/VitruvianToolKit/Tool.swift",
        "docs/writing-a-tool.md",
    ],
    main = "docs/guide_test.py",
    deps = ["@pip//jsonschema"],
)

# The version in release-please's two files and the one `--version` prints
# agree. Plain Python, so the Linux lane runs it too.
py_test(
    name = "release_version_test",
    size = "small",
    srcs = ["release_version_test.py"],
    data = [
        ".release-please-manifest.json",
        "Sources/VitruvianToolCLI/Words.swift",
        "release-please-config.json",
    ],
    main = "release_version_test.py",
)

pipeline_unit(
    name = "vitruvian-sdk",
    persona = "platform",
    runner = "xcode-27",
    test_targets = [
        ":VitruvianToolCLITests",
        ":VitruvianToolKitTests",
        ":VitruvianToolProtocolTests",
        ":conformance_test",
        ":guide_test",
        ":init_test",
        ":mirror_workflows_test",
        ":protocol_examples_test",
        ":release_version_test",
        ":samples_test",
        ":swift_samples_test",
        ":swift_template_test",
        ":templates_in_sync_test",
    ],
    tier = "L1",
    timeout_minutes = 30,
)
