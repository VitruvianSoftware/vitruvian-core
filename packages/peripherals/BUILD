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

load("@build_bazel_rules_apple//apple:macos.bzl", "macos_command_line_application")
load("@build_bazel_rules_swift//swift:swift_library.bzl", "swift_library")
load("@build_bazel_rules_swift//swift:swift_test.bzl", "swift_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("//tools/delivery:defs.bzl", "delivery")
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

# The executable's top-level code (main.swift), as a library so the
# command-line application below can sign it. Package.swift's
# GravaStarMouseTool executable target.
swift_library(
    name = "GravaStarMouseTool",
    srcs = glob(["Sources/gravastar-mouse/**/*.swift"]),
    module_name = "GravaStarMouseTool",
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":GravaStarCLI"],
)

# bazel run --config=macos-app //packages/peripherals:gravastar-mouse -- signal success
#
# A signed command-line tool rather than a bare swift_binary: the Vitruvian app
# carries it in Contents/Helpers (codesign --deep checks every nested binary),
# and the release build makes it universal with --macos_cpus (publish.sh).
macos_command_line_application(
    name = "gravastar-mouse",
    bundle_id = "com.vitruviansoftware.gravastar-mouse",
    minimum_os_version = "14.0",
    target_compatible_with = ["@platforms//os:macos"],
    visibility = ["//visibility:public"],
    deps = [":GravaStarMouseTool"],
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

# Read by //tools/delivery/gen's guard that every `run:` in the generated
# workflow points at a script that exists and is executable.
exports_files(["publish.sh"])

# Build the universal binary + upload it (and, for a release, the Homebrew
# formula). The generated delivery workflow runs the script directly
# (`bash packages/peripherals/publish.sh`); this target is the break-glass path
# and what the delivery() below names as `run`.
sh_binary(
    name = "publish",
    srcs = ["publish.sh"],
    tags = ["manual"],
)

# Delivery unit: the gravastar-mouse release ladder.
#   beta        on every affected push to main -> rolling prerelease
#               gravastar-mouse-beta-latest (asset clobbered, tag moved to HEAD);
#   production  on the release-please release gravastar-mouse-vX.Y.Z -> asset
#               attached to that release, then the homebrew-tap formula.
# The release-please machinery that cuts the production tag lives in
# .github/workflows/gravastar-mouse-release.yaml (release machinery, not
# delivery -- the same split as esp32-s3 and vitruvian).
delivery(
    # Not "gravastar-mouse": that is the binary's target, and gazelle reads
    # this macro call as a rule of the same name.
    name = "gravastar-mouse-publish",
    app = "gravastar-mouse",
    environments = [
        "beta",
        "production",
    ],
    # Path-only mode: this regex IS the unit's complete trigger set
    # (tools/ci/deploy-affected.sh step 2), so it names the whole package.
    extra_paths = ["packages/peripherals/"],
    # No GitHub Environment: the publish binds none; it uploads with the run's
    # own GITHUB_TOKEN under a job-level contents: write.
    github_environment = "",
    kind = "publish",
    # No job of its own preceded this unit. Its steps are vitruvian's publish
    # job (Xcode, Bazel, one script) minus the app signing, so that is the
    # provenance recorded.
    legacy_job = "package",
    legacy_workflow = ".github/workflows/vitruvian-release.yaml",
    promotion = "release:gravastar-mouse-v",
    render = "transcribed",
    run = "//packages/peripherals:publish",
)
