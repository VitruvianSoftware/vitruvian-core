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

# //packages/peripherals: drive the RGB LED of a GravaStar (CompX chipset)
# mouse over IOKit HID, and use it as a status light. See README.md.
#
# Swift has no Gazelle extension here, so this file is hand-written.
# gazelle:ignore
#
# MUST MIRROR Package.swift target for target (the nexus-agent mirror-breakage
# incident, apps/desktop/nexus-agent/macos/Package.swift). Every target is
# constrained to macOS so a Linux `bazel build //...` skips it rather than
# failing to find an Apple toolchain.

load("@build_bazel_rules_swift//swift:swift_binary.bzl", "swift_binary")
load("@build_bazel_rules_swift//swift:swift_library.bzl", "swift_library")
load("@build_bazel_rules_swift//swift:swift_test.bzl", "swift_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# The pure codec: frames, checksums, the lighting record. No IOKit.
swift_library(
    name = "CompXProtocol",
    srcs = glob(["Sources/CompXProtocol/**/*.swift"]),
    module_name = "CompXProtocol",
    target_compatible_with = ["@platforms//os:macos"],
    visibility = ["//visibility:public"],
)

# The transport seam plus the IOKit implementation and the GravaStarMouse facade.
swift_library(
    name = "CompXHID",
    srcs = glob(["Sources/CompXHID/**/*.swift"]),
    module_name = "CompXHID",
    target_compatible_with = ["@platforms//os:macos"],
    visibility = ["//visibility:public"],
    deps = [":CompXProtocol"],
)

# working/success/failure/warning/attention -> lighting presets, with
# baseline save/restore. What notification sources depend on.
swift_library(
    name = "StatusSignals",
    srcs = glob(["Sources/StatusSignals/**/*.swift"]),
    module_name = "StatusSignals",
    target_compatible_with = ["@platforms//os:macos"],
    visibility = ["//visibility:public"],
    deps = [
        ":CompXHID",
        ":CompXProtocol",
    ],
)

# Argument parsing and command execution, as a library so the tests can link
# it without the executable's top-level code (which would collide with
# XCTest's `main`, #807).
swift_library(
    name = "GravaStarCLI",
    srcs = glob(["Sources/GravaStarCLI/**/*.swift"]),
    module_name = "GravaStarCLI",
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        ":CompXHID",
        ":CompXProtocol",
        ":StatusSignals",
    ],
)

# bazel run //packages/peripherals:gravastar-mouse -- signal success
swift_binary(
    name = "gravastar-mouse",
    srcs = glob(["Sources/gravastar-mouse/**/*.swift"]),
    module_name = "GravaStarMouseTool",
    target_compatible_with = ["@platforms//os:macos"],
    visibility = ["//visibility:public"],
    deps = [":GravaStarCLI"],
)

# No hardware needed: the device is a scripted MockTransport. macOS-only and
# `manual`, like every swift_test here, so the Linux lane never names it; the
# `peripherals` pipeline unit below runs it by explicit label on xcode-27.
swift_test(
    name = "PeripheralsTests",
    size = "small",
    srcs = glob(["Tests/PeripheralsTests/**/*.swift"]),
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        ":CompXHID",
        ":CompXProtocol",
        ":GravaStarCLI",
        ":StatusSignals",
    ],
)

pipeline_unit(
    name = "peripherals",
    persona = "platform",
    runner = "xcode-27",
    test_targets = [":PeripheralsTests"],
    tier = "L1",
    timeout_minutes = 30,
)
