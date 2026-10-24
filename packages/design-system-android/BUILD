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

# //packages/design-system-android: Vitruvian for Jetpack Compose.
#
# The Kotlin half of the design system. The web package next door
# (//packages/design-system) is the source of truth for the language; this
# module is the Compose realisation of the mapping written down in that
# package's ANDROID.md. It has no app dependencies, on purpose: an app
# depends on the design system, never the other way round.
#
# Gazelle has no Kotlin/Android extension configured in this repo, so this
# file is hand-authored like //packages/design-system's.
# gazelle:ignore

load("@rules_kotlin//kotlin:android.bzl", "kt_android_library")
load("@rules_kotlin//kotlin:core.bzl", "kt_compiler_plugin")
load("@rules_kotlin//kotlin:jvm.bzl", "kt_jvm_library", "kt_jvm_test")
load("@rules_python//python:defs.bzl", "py_test")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//tools/doctor:defs.bzl", "doctor")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

package(default_visibility = ["//visibility:public"])

# The overlay rules -- where a long option list opens, what a tap on it does,
# and how much padding keeps an overlay clear of the bars and keyboard -- are
# plain Kotlin with no Compose in them. They are their own JVM library, which
# :lib depends on rather than compiling a second copy, and a plain JUnit test
# pins them: no device, no emulator.
OVERLAY_RULES = [
    "src/main/kotlin/dev/vitruvian/design/OptionList.kt",
    "src/main/kotlin/dev/vitruvian/design/SafeArea.kt",
]

# The Compose compiler plugin.
#
# Since Kotlin 2.0 the Compose compiler ships with the Kotlin release rather
# than as a separate androidx artifact, but its plugin id is unchanged. Every
# target that compiles @Composable code needs it - both this module and the
# app - so it lives here and is public.
kt_compiler_plugin(
    name = "compose_compiler",
    id = "androidx.compose.compiler.plugins.kotlin",
    target_embedded_compiler = True,
    visibility = ["//visibility:public"],
    deps = ["@maven//:org_jetbrains_kotlin_kotlin_compose_compiler_plugin_embeddable"],
)

# The Vitruvian Compose library: tokens, primitives and the mobile shell.
#
# An Android library rather than a plain JVM one because the module ships
# resources: res/font carries JetBrains Mono and IBM Plex Sans, and the
# generated R class is what Theme.kt resolves the families through.
kt_android_library(
    name = "lib",
    srcs = glob(
        ["src/main/kotlin/**/*.kt"],
        exclude = OVERLAY_RULES,
    ),
    custom_package = "dev.vitruvian.design",
    manifest = "src/main/AndroidManifest.xml",
    plugins = [":compose_compiler"],
    resource_files = glob(["src/main/res/**"]),
    deps = [
        ":overlay_rules",
        "@maven//:androidx_annotation_annotation",
        "@maven//:androidx_compose_animation_animation",
        "@maven//:androidx_compose_animation_animation_core",
        "@maven//:androidx_compose_foundation_foundation",
        "@maven//:androidx_compose_foundation_foundation_layout",
        "@maven//:androidx_compose_runtime_runtime",
        "@maven//:androidx_compose_ui_ui",
        "@maven//:androidx_compose_ui_ui_graphics",
        "@maven//:androidx_compose_ui_ui_text",
        "@maven//:androidx_compose_ui_ui_unit",
        "@maven//:org_jetbrains_kotlinx_kotlinx_coroutines_android",
    ],
)

kt_jvm_library(
    name = "overlay_rules",
    srcs = OVERLAY_RULES,
)

kt_jvm_test(
    name = "option_list_test",
    size = "small",
    srcs = ["src/test/kotlin/dev/vitruvian/design/OptionListTest.kt"],
    test_class = "dev.vitruvian.design.OptionListTest",
    deps = [
        ":overlay_rules",
        "@maven//:junit_junit",
    ],
)

kt_jvm_test(
    name = "safe_area_test",
    size = "small",
    srcs = ["src/test/kotlin/dev/vitruvian/design/SafeAreaTest.kt"],
    test_class = "dev.vitruvian.design.SafeAreaTest",
    deps = [
        ":overlay_rules",
        "@maven//:junit_junit",
    ],
)

# The tokens are generated, never hand-edited (ANDROID.md). This test is the
# gate that says so: it regenerates VitruvianTokens.kt from tokens.json and
# fails if the checked-in file differs, so web and Android cannot drift
# without CI noticing.
sh_test(
    name = "tokens_are_current",
    # tools/ is its own package (it has a BUILD), so these cross a package
    # boundary and need full labels -- a "tools/..." path label would resolve
    # into this package and fail to load. Both are exported by tools/BUILD.
    srcs = ["//packages/design-system-android/tools:tokens_are_current.sh"],
    data = [
        "src/main/kotlin/dev/vitruvian/design/VitruvianTokens.kt",
        "//packages/design-system:src/tokens.json",
        "//packages/design-system-android/tools:gen_tokens",
        "//packages/design-system-android/tools:kt_license_header.txt",
        "//tools/format:ktfmt",
    ],
    env = {
        "GENERATOR": "$(rlocationpath //packages/design-system-android/tools:gen_tokens)",
        "KTFMT": "$(rlocationpath //tools/format:ktfmt)",
        "TOKENS": "$(rlocationpath //packages/design-system:src/tokens.json)",
        "HEADER": "$(rlocationpath //packages/design-system-android/tools:kt_license_header.txt)",
        "CHECKED_IN": "$(rlocationpath src/main/kotlin/dev/vitruvian/design/VitruvianTokens.kt)",
    },
    deps = ["@bazel_tools//tools/bash/runfiles"],
)

py_test(
    name = "parity_test",
    size = "small",
    srcs = ["//packages/design-system-android/tools:parity_test.py"],
    data = glob(["src/main/kotlin/**/*.kt"]) + [
        "//packages/design-system:src/Icons.tsx",
        "//packages/design-system:src/Illustrations.tsx",
    ],
    main = "//packages/design-system-android/tools:parity_test.py",
)

# Developer-environment check: `bazel run //packages/design-system-android:doctor`.
doctor(
    name = "doctor",
    label = "design-system-android (Vitruvian for Compose)",
    required = [
        "bazel",
        "git",
        "python3",
    ],
)

pipeline_unit(
    name = "design-system-android",
    persona = "frontend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":lib",
        ":option_list_test",
        ":parity_test",
        ":safe_area_test",
        ":tokens_are_current",
    ],
    tier = "L1",
    timeout_minutes = 20,
)
