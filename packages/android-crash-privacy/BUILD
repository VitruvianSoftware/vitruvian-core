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

# //packages/android-crash-privacy: Shared privacy-hardened Sentry helper for Android apps.
#
# Gazelle has no Kotlin/Android extension configured in this repo, so this
# file is hand-authored like //packages/design-system/android's.
# gazelle:ignore

load("@rules_java//java:java_import.bzl", "java_import")
load("@rules_kotlin//kotlin:android.bzl", "kt_android_library")
load("@rules_kotlin//kotlin:jvm.bzl", "kt_jvm_test")

package(default_visibility = ["//visibility:public"])

exports_files(["BUILD"])

kt_android_library(
    name = "android-crash-privacy",
    srcs = ["src/main/kotlin/dev/vitruvian/crashprivacy/CrashPrivacy.kt"],
    custom_package = "dev.vitruvian.crashprivacy",
    manifest = "src/main/AndroidManifest.xml",
    deps = [
        "@maven//:io_sentry_sentry",
        "@maven//:io_sentry_sentry_android_core",
    ],
)

java_import(
    name = "android_sdk_stub_jar",
    testonly = True,
    jars = ["@androidsdk//:platforms/android-35/android.jar"],
)

kt_jvm_test(
    name = "crash_privacy_test",
    size = "small",
    srcs = ["src/test/kotlin/dev/vitruvian/crashprivacy/CrashPrivacyTest.kt"],
    data = ["src/main/kotlin/dev/vitruvian/crashprivacy/CrashPrivacy.kt"],
    test_class = "dev.vitruvian.crashprivacy.CrashPrivacyTest",
    runtime_deps = [":android_sdk_stub_jar"],
    deps = [
        ":android-crash-privacy",
        "@maven//:io_sentry_sentry",
        "@maven//:io_sentry_sentry_android_core",
        "@maven//:junit_junit",
    ],
)
