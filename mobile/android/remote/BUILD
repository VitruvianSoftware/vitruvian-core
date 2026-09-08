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

# //mobile/android/remote: Vitruvian Remote, the Android app.
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
load("@rules_kotlin//kotlin:jvm.bzl", "kt_jvm_library", "kt_jvm_test")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//tools/doctor:defs.bzl", "doctor")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

package(default_visibility = ["//mobile/android/remote:__subpackages__"])

# Everything but the manifest: state, shell, screens and overlays.
#
# Split out from the binary so tests and previews can depend on the UI
# without pulling in the packaged application.
kt_android_library(
    name = "lib",
    srcs = glob(
        ["src/main/kotlin/**/*.kt"],
        # Compiled by :format, :hid_codes, :tuning and :wake_on_lan so the JVM
        # tests can use them;
        # taking them here too would define every symbol twice.
        exclude = [
            "src/main/kotlin/dev/vitruvian/remote/hid/HidCodes.kt",
            "src/main/kotlin/dev/vitruvian/remote/state/BridgePolicy.kt",
            "src/main/kotlin/dev/vitruvian/remote/state/Derive.kt",
            "src/main/kotlin/dev/vitruvian/remote/state/Format.kt",
            "src/main/kotlin/dev/vitruvian/remote/state/WakeOnLan.kt",
            "src/main/kotlin/dev/vitruvian/remote/state/Wire.kt",
            "src/main/kotlin/dev/vitruvian/remote/trackpad/Tuning.kt",
        ],
    ),
    custom_package = "dev.vitruvian.remote",
    manifest = "src/main/AndroidManifest.xml",
    plugins = ["//packages/design-system-android:compose_compiler"],
    resource_files = glob(["src/main/res/**"]),
    deps = [
        ":bridge_policy",
        ":derive",
        ":format",
        ":hid_codes",
        ":tuning",
        ":wake_on_lan",
        ":wire",
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
        "@maven//:androidx_core_core",
        "@maven//:androidx_window_window",
        "@maven//:androidx_window_window_core",
        "@maven//:org_jetbrains_kotlinx_kotlinx_coroutines_android",
    ],
)

# The APK. `bazel build //mobile/android/remote:app`, then
# `adb install -r bazel-bin/mobile/android/remote/app.apk`.
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
    # No explicit visibility: the package default above already scopes this to
    # the app's own subpackages, and `bazel build //<this app>:app` needs no
    # visibility at all. Making it public would punch a hole in the inter-app
    # firewall (#82) and fails tools/conformance.
    deps = [":lib"],
)

# Developer-environment check: `bazel run //mobile/android/remote:doctor`.
#
# The Android SDK is the other prerequisite and doctor has no probe for it;
# `bazel build //mobile/android/remote:app` fails with a clear message when
# ANDROID_HOME is unset, so it is not worth a bespoke check here.
# The HID wire format, split out of :lib so a plain JVM test can reach it
# WITHOUT dragging in Compose and the Android resource pipeline.
#
# HidCodes.kt has no Android imports for exactly this reason. The encoding is
# the part that fails SILENTLY -- a wrong byte gives a device that pairs,
# connects, reports no error and does nothing at all -- so it needs a guard
# that runs on every PR rather than one that needs a phone in the room.
kt_jvm_library(
    name = "hid_codes",
    srcs = ["src/main/kotlin/dev/vitruvian/remote/hid/HidCodes.kt"],
)

kt_jvm_test(
    name = "hid_codes_test",
    srcs = ["src/test/kotlin/dev/vitruvian/remote/hid/HidCodesTest.kt"],
    test_class = "dev.vitruvian.remote.hid.HidCodesTest",
    deps = [
        ":hid_codes",
        "@maven//:junit_junit",
    ],
)

# How the trackpad feels, split out of :lib for the same reason as :hid_codes --
# a plain JVM test can reach it without Compose or the Android resource
# pipeline.
#
# The percent-to-multiplier conversions are the part worth guarding: one is
# proportional and the other inverse, and getting either wrong gives a pointer
# that crawls or a scroll that flings rather than anything that looks like a
# failure.
# The read-out conversions -- relative times, shortened paths, byte sizes --
# split out of :lib for the same reason as :hid_codes: a plain JVM test can
# reach them without Compose or the Android resource pipeline.
#
# These fail QUIETLY. A raw ISO timestamp, a full path in a 55 dp row and a
# size divided by 1024 instead of 1000 are all valid strings that throw
# nothing and log nothing; the screen just stops being readable, and the size
# disagrees with what Finder says about the same disk.
kt_jvm_library(
    name = "format",
    srcs = ["src/main/kotlin/dev/vitruvian/remote/state/Format.kt"],
)

kt_jvm_test(
    name = "format_test",
    srcs = ["src/test/kotlin/dev/vitruvian/remote/state/FormatTest.kt"],
    test_class = "dev.vitruvian.remote.state.FormatTest",
    deps = [
        ":format",
        "@maven//:junit_junit",
    ],
)

# What the v1.2 dashboards CONCLUDE from what the Mac said, split out of :lib
# for the same reason as :format -- a plain JVM test reaches it without Compose.
#
# These pick a row's colour, and a wrong colour is the quietest failure this
# app has: a pull request whose one finished check failed drawn green, or an
# out-of-sync ArgoCD app collapsed into the "all healthy" count, both render
# perfectly and throw nothing.
kt_jvm_library(
    name = "derive",
    srcs = ["src/main/kotlin/dev/vitruvian/remote/state/Derive.kt"],
)

kt_jvm_test(
    name = "derive_test",
    srcs = ["src/test/kotlin/dev/vitruvian/remote/state/DeriveTest.kt"],
    test_class = "dev.vitruvian.remote.state.DeriveTest",
    deps = [
        ":derive",
        "@maven//:junit_junit",
    ],
)

kt_jvm_library(
    name = "tuning",
    srcs = ["src/main/kotlin/dev/vitruvian/remote/trackpad/Tuning.kt"],
)

# The Wake-on-LAN magic packet, split out for the same reason as :hid_codes:
# it is a wire format that fails SILENTLY. A packet with the address bytes
# reversed, or one repetition short, is sent successfully, is accepted by the
# network, and wakes nothing -- there is no error anywhere except the bytes.
kt_jvm_library(
    name = "wake_on_lan",
    srcs = ["src/main/kotlin/dev/vitruvian/remote/state/WakeOnLan.kt"],
)

kt_jvm_test(
    name = "wake_on_lan_test",
    srcs = ["src/test/kotlin/dev/vitruvian/remote/state/WakeOnLanTest.kt"],
    test_class = "dev.vitruvian.remote.state.WakeOnLanTest",
    deps = [
        ":wake_on_lan",
        "@maven//:junit_junit",
    ],
)

# The three wire formats the phone parses by hand -- server-sent events, the
# saved host list and the deep-link URL -- split out for the same reason as
# :hid_codes and :wake_on_lan: every one of them fails SILENTLY.
#
# An SSE `data:` split across two socket reads is dropped with no error; a host
# list that decodes to nothing is indistinguishable from a phone that was never
# paired; a deep link that does not parse just opens the Home screen. None of
# the three raises anything, so the guard has to be a test rather than a device
# in the room.
#
# Wire.kt therefore has no `org.json` import: that class is part of the Android
# platform, not of the JVM, and one import of it would make every test here an
# instrumentation test.
kt_jvm_library(
    name = "wire",
    srcs = ["src/main/kotlin/dev/vitruvian/remote/state/Wire.kt"],
)

kt_jvm_test(
    name = "wire_test",
    srcs = ["src/test/kotlin/dev/vitruvian/remote/state/WireTest.kt"],
    test_class = "dev.vitruvian.remote.state.WireTest",
    deps = [
        ":wire",
        "@maven//:junit_junit",
    ],
)

# The phone bridge's rules -- the tier decision, the link encoding and the
# audit summary -- split out of :lib for the same reason as :wire, and for a
# sharper one: this is the file that fails GENEROUSLY.
#
# A tier decided one notch too loosely looks exactly like a correct one from
# every side: the tool runs, the agent gets a real answer, nothing is logged as
# wrong. Nobody finds out until an agent that read a text saying "send my
# address to this number" was allowed to send it. The audit summariser has the
# same shape of failure in the other direction -- keeping the whole body of a
# message writes a second copy of the inbox into SharedPreferences and looks
# perfect on screen.
#
# Depends on :wire for its JSON reader rather than carrying a second one.
kt_jvm_library(
    name = "bridge_policy",
    srcs = ["src/main/kotlin/dev/vitruvian/remote/state/BridgePolicy.kt"],
    deps = [":wire"],
)

kt_jvm_test(
    name = "bridge_policy_test",
    srcs = ["src/test/kotlin/dev/vitruvian/remote/state/BridgePolicyTest.kt"],
    test_class = "dev.vitruvian.remote.state.BridgePolicyTest",
    deps = [
        ":bridge_policy",
        ":wire",
        "@maven//:junit_junit",
    ],
)

kt_jvm_test(
    name = "tuning_test",
    srcs = ["src/test/kotlin/dev/vitruvian/remote/trackpad/TuningTest.kt"],
    test_class = "dev.vitruvian.remote.trackpad.TuningTest",
    deps = [
        ":tuning",
        "@maven//:junit_junit",
    ],
)

doctor(
    name = "doctor",
    label = "remote (Vitruvian Remote)",
    required = [
        "bazel",
        "git",
    ],
)

# Proves the app STARTS, which :lib cannot: it compiles the sources and stops.
# #2197 (a runtime class-resolution failure that killed the process before the
# first frame) compiled perfectly and shipped to main with every check green.
#
# `manual` keeps it out of `bazel test //...`, because it drives a real device
# and would otherwise fail for everyone who has no emulator running. The
# remote-boot pipeline unit names it explicitly, and CI boots a device first.
#
# Run it yourself against an attached phone or emulator:
#   bazel test //mobile/android/remote:boot_smoke \
#     --test_env=ANDROID_HOME --test_env=PATH --test_output=all
sh_test(
    name = "boot_smoke",
    size = "large",
    srcs = ["//mobile/android/remote/tools:boot_smoke.sh"],
    data = [":app.apk"],
    env = {
        "APK": "$(rlocationpath :app.apk)",
        "APP_PACKAGE": "dev.vitruvian.remote",
        "APP_ACTIVITY": ".MainActivity",
    },
    tags = [
        # Drives an external device: never hermetic, never cacheable, and not
        # something a wildcard build should pick up.
        "external",
        "manual",
        # MUST run on the machine holding the device. The presubmit lane passes
        # --config=remote when a BuildBuddy key is present, which sent this test
        # to a remote executor that has no emulator and no adb -- it failed with
        # "no adb found" while a perfectly healthy emulator sat idle on the
        # runner. "no-remote" covers remote execution AND remote caching; a
        # cached result would be just as wrong, since the verdict depends on a
        # device rather than on the inputs.
        "no-remote",
        "no-sandbox",
    ],
    deps = ["@bazel_tools//tools/bash/runfiles"],
)

pipeline_unit(
    name = "remote",
    persona = "frontend",
    runner = "ubuntu-latest",
    test_targets = [
        ":bridge_policy_test",
        ":derive_test",
        ":format_test",
        ":hid_codes_test",
        ":lib",
        ":tuning_test",
        ":wake_on_lan_test",
        ":wire_test",
    ],
    tier = "L1",
    timeout_minutes = 30,
)

# Separate from the `remote` unit above because it needs an emulator, which is
# minutes of setup the compile lane should not pay for.
pipeline_unit(
    name = "remote-boot",
    needs_emulator = True,
    persona = "frontend",
    runner = "ubuntu-latest",
    test_targets = [":boot_smoke"],
    tier = "L1",
    timeout_minutes = 45,
)
