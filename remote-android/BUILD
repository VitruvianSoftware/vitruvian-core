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

# //remote-android: Vitruvian Remote, the Android app.
#
# A remote control and observability console for a Mac, foldable-first. The
# UI is built entirely from //packages/design-system-android; nothing in here
# defines a colour, a size or a font.
#
# Inter-app boundary (#82): internals default to this app's own visibility so
# no other top-level app can depend on them.
#
# Gazelle has no Kotlin/Android extension configured in this repo, so this
# file is hand-authored.
# gazelle:ignore

load("@rules_android//android:rules.bzl", "android_binary")
load("@rules_kotlin//kotlin:android.bzl", "kt_android_library")
load("//tools/doctor:defs.bzl", "doctor")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

package(default_visibility = ["//remote-android:__subpackages__"])

# Everything but the manifest: state, shell, screens and overlays.
#
# Split out from the binary so tests and previews can depend on the UI
# without pulling in the packaged application.
kt_android_library(
    name = "lib",
    srcs = glob(["src/main/kotlin/**/*.kt"]),
    custom_package = "dev.vitruvian.remote",
    manifest = "src/main/AndroidManifest.xml",
    plugins = ["//packages/design-system-android:compose_compiler"],
    resource_files = glob(["src/main/res/**"]),
    deps = [
        "//packages/design-system-android:lib",
        "@maven//:androidx_activity_activity_compose",
        "@maven//:androidx_compose_animation_animation",
        "@maven//:androidx_compose_foundation_foundation",
        "@maven//:androidx_compose_foundation_foundation_layout",
        "@maven//:androidx_compose_runtime_runtime",
        "@maven//:androidx_compose_ui_ui",
        "@maven//:androidx_compose_ui_ui_graphics",
        "@maven//:androidx_compose_ui_ui_text",
        "@maven//:androidx_compose_ui_ui_unit",
        "@maven//:androidx_window_window",
        "@maven//:androidx_window_window_core",
        "@maven//:org_jetbrains_kotlinx_kotlinx_coroutines_android",
    ],
)

# The APK. `bazel build //remote-android:app`, then
# `adb install -r bazel-bin/remote-android/app.apk`.
#
# Debug-signed only: this app has no release pipeline yet, and shipping an
# unsigned-for-release target that looks releasable is worse than not having
# one. See README.md for what a release would need.
android_binary(
    name = "app",
    custom_package = "dev.vitruvian.remote",
    manifest = "src/main/AndroidManifest.xml",
    manifest_values = {
        "applicationId": "dev.vitruvian.remote",
        # API 26 is the floor because the launcher icon is adaptive; the
        # glass surfaces need 31 and fall back to an opaque surface below it,
        # exactly as ANDROID.md prescribes.
        "minSdkVersion": "26",
        "targetSdkVersion": "35",
        "versionCode": "1",
        "versionName": "0.1.0",
    },
    visibility = ["//visibility:public"],
    deps = [":lib"],
)

# Developer-environment check: `bazel run //remote-android:doctor`.
#
# The Android SDK is the other prerequisite and doctor has no probe for it;
# `bazel build //remote-android:app` fails with a clear message when
# ANDROID_HOME is unset, so it is not worth a bespoke check here.
doctor(
    name = "doctor",
    label = "remote-android (Vitruvian Remote)",
    required = [
        "bazel",
        "git",
    ],
)

pipeline_unit(
    name = "remote-android",
    persona = "frontend",
    runner = "ubuntu-latest",
    test_targets = [":lib"],
    tier = "L1",
    timeout_minutes = 30,
)
