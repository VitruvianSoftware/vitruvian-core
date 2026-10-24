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

load("@rules_android//android:rules.bzl", "android_binary")
load("@rules_kotlin//kotlin:android.bzl", "kt_android_library")
load("//tools/doctor:defs.bzl", "doctor")

package(default_visibility = ["//apps/mobile/wearos:__subpackages__"])

kt_android_library(
    name = "lib",
    srcs = glob(["src/main/kotlin/**/*.kt"]),
    custom_package = "dev.vitruvian.wear.home",
    manifest = "src/main/AndroidManifest.xml",
    plugins = ["//packages/design-system-android:compose_compiler"],
    resource_files = glob(["src/main/res/**"]),
    deps = [
        "//apps/mobile/wearos/apps/common",
        "//packages/design-system-android:lib",
        "@maven//:androidx_activity_activity_compose",
        "@maven//:androidx_compose_foundation_foundation",
        "@maven//:androidx_compose_foundation_foundation_layout",
        "@maven//:androidx_compose_runtime_runtime",
        "@maven//:androidx_compose_ui_ui",
        "@maven//:androidx_compose_ui_ui_graphics",
        "@maven//:androidx_compose_ui_ui_unit",
        "@maven//:androidx_core_core",
    ],
)

android_binary(
    name = "app",
    custom_package = "dev.vitruvian.wear.home",
    manifest = "src/main/AndroidManifest.xml",
    manifest_values = {
        "applicationId": "dev.vitruvian.wear.home",
        "minSdkVersion": "30",
        "targetSdkVersion": "35",
        "versionCode": "1",
        "versionName": "0.1.0",
    },
    deps = [":lib"],
)

doctor(
    name = "doctor",
    label = "wear-home-control (Wear OS Smart Home, Speaker & Roborock Controller)",
    required = [
        "bazel",
        "git",
    ],
)
